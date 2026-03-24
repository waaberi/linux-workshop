from typing import Mapping

def authenticate(
    username: str,
    password: str,
    service: str = "login",
    env: Mapping[str, str] | None = None,
    call_end: bool = True,
    encoding: str = "utf-8",
    resetcreds: bool = True,
    print_failure_messages: bool = False,
) -> bool: ...
