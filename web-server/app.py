from __future__ import annotations

from contextlib import asynccontextmanager
import hmac
from pathlib import Path
from urllib.parse import urlencode

from fastapi import FastAPI, Form, Request
from fastapi.exception_handlers import http_exception_handler
from fastapi.responses import (
    HTMLResponse,
    PlainTextResponse,
    RedirectResponse,
    Response,
)
from fastapi.templating import Jinja2Templates
from starlette.exceptions import HTTPException as StarletteHTTPException

from model import (
    APP,
    COOKIE_NAME,
    SESSION_TTL,
    USERNAME_RE,
    audit,
    authenticate_with_pam,
    create_account,
    init_state,
    is_student_user,
    load_session,
    machine_record,
    make_session,
    registrations_by_username,
    reset_machine,
    validate_registration,
)


templates = Jinja2Templates(directory=str(Path(__file__).resolve().parent / "views"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_state()
    yield


app = FastAPI(
    title="Workshop Web",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
    lifespan=lifespan,
)


def current_session(request: Request) -> dict[str, str] | None:
    return load_session(request.cookies.get(COOKIE_NAME))


def with_message(path: str, *, notice: str = "", error: str = "") -> str:
    query: dict[str, str] = {}
    if notice:
        query["notice"] = notice
    if error:
        query["error"] = error
    return path if not query else f"{path}?{urlencode(query)}"


def home_for(session: dict[str, str]) -> str:
    return "/dashboard"


def render(request: Request, template_name: str, **context: object) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        template_name,
        {
            "app": APP,
            "session": current_session(request),
            "error": request.query_params.get("error", ""),
            "notice": request.query_params.get("notice", ""),
            **context,
        },
    )


def redirect(
    location: str, *, session_value: str | None = None, clear_session: bool = False
) -> RedirectResponse:
    response = RedirectResponse(location, status_code=303)
    if session_value is not None:
        response.set_cookie(
            COOKIE_NAME,
            session_value,
            max_age=SESSION_TTL,
            httponly=True,
            samesite="lax",
            path="/",
        )
    if clear_session:
        response.delete_cookie(COOKIE_NAME, path="/")
    return response


def require_session(request: Request) -> dict[str, str] | None:
    session = current_session(request)
    return session


def valid_csrf(session: dict[str, str] | None, token: str) -> bool:
    if not session or not token:
        return False
    return hmac.compare_digest(token, session["csrf"])


def reset_notice(username: str, archive_refs: list[str], missing: bool) -> str:
    message = (
        f"No machine existed for {username}."
        if missing
        else f"Machine for {username} reset. A fresh one will be created on the next SSH login."
    )
    if archive_refs:
        message += f" Archive: {archive_refs[0]}"
    return message


@app.get("/healthz")
def healthz() -> PlainTextResponse:
    return PlainTextResponse("ok\n")


@app.exception_handler(StarletteHTTPException)
async def http_error(request: Request, exc: StarletteHTTPException) -> Response:
    if exc.status_code != 404:
        return await http_exception_handler(request, exc)
    return templates.TemplateResponse(
        request,
        "not_found.html",
        {
            "request": request,
            "title": "Not Found",
            "app": APP,
            "session": current_session(request),
            "error": "",
            "notice": "",
        },
        status_code=404,
    )


@app.get("/", response_class=HTMLResponse, response_model=None)
def home(request: Request) -> Response:
    session = current_session(request)
    if session:
        return redirect(home_for(session))
    return render(request, "home.html", title=APP.title)


@app.get("/dashboard", response_class=HTMLResponse, response_model=None)
def dashboard(request: Request) -> Response:
    session = require_session(request)
    if not session:
        return redirect(with_message("/", error="Sign in first."))
    if session["role"] != "student":
        return redirect(
            with_message("/", error="Student web access only."), clear_session=True
        )
    registration = registrations_by_username().get(session["username"])
    record = machine_record(session["username"], registration)
    latest_archive = record.archive_refs[0] if record.archive_refs else "-"
    return render(
        request,
        "student_dashboard.html",
        title="Student Dashboard",
        record=record,
        latest_archive=latest_archive,
    )


@app.post("/register")
def register(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    password_confirm: str = Form(...),
) -> Response:
    username = username.strip().lower()
    remote_ip = request.client.host if request.client else "unknown"
    error = validate_registration(username, password, password_confirm, remote_ip)
    if error:
        return redirect(with_message("/", error=error))
    try:
        create_account(username, password, remote_ip)
    except RuntimeError as exc:
        return redirect(with_message("/", error=str(exc)))
    audit(username, "register", username, f"Claimed from {remote_ip}")
    return redirect(
        with_message("/dashboard", notice=f"Account {username} is ready."),
        session_value=make_session(username, "student"),
    )


@app.post("/login")
def login(
    username: str = Form(...),
    password: str = Form(...),
) -> Response:
    username = username.strip()
    if not is_student_user(username):
        return redirect(
            with_message(
                "/",
                error="The website is only for student accounts. Operator tasks are CLI-only.",
            )
        )
    if not authenticate_with_pam(username, password):
        return redirect(
            with_message("/", error="Login failed. Check the username and password.")
        )
    return redirect(
        home_for({"username": username, "role": "student"}),
        session_value=make_session(username, "student"),
    )


@app.post("/logout")
def logout(request: Request, csrf: str = Form("")) -> Response:
    session = require_session(request)
    if not valid_csrf(session, csrf):
        return redirect(
            with_message("/", error="Your session expired. Sign in again."),
            clear_session=True,
        )
    return redirect("/", clear_session=True)


@app.post("/machine/reset")
def reset_student_machine(
    request: Request,
    csrf: str = Form(""),
    password: str = Form(...),
) -> Response:
    session = require_session(request)
    if not session or session["role"] != "student" or not valid_csrf(session, csrf):
        return redirect(
            with_message("/", error="Sign in again before changing machines.")
        )
    username = session["username"]
    if not USERNAME_RE.fullmatch(username):
        return redirect(with_message("/dashboard", error="Invalid username."))
    if not authenticate_with_pam(username, password):
        return redirect(
            with_message("/dashboard", error="Password confirmation failed.")
        )
    try:
        result = reset_machine(username)
    except RuntimeError as exc:
        return redirect(with_message("/dashboard", error=str(exc)))
    archive_refs = result["ARCHIVE_REF"]
    archives = ", ".join(archive_refs) or "no archive"
    audit(username, "reset-machine", username, f"Archived machine as {archives}")
    return redirect(
        with_message(
            "/dashboard",
            notice=reset_notice(username, archive_refs, result["RESULT"] == "missing"),
        )
    )
