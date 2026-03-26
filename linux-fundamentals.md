# Linux Fundamentals

# Linux Fundamentals & Development Environment

*Getting started with Linux.*


---

# Introduction

Linux is a free and open-source operating system **kernel** created by Linus Torvalds in 1991. Today, Linux powers a large portion of the world's computing infrastructure.


:::info
Linux itself is technically just the **kernel**, which manages hardware and system resources. Most systems people refer to as "Linux" are actually **GNU/Linux distributions**, which combine the Linux kernel with tools from the GNU project and other open-source software.

:::

## Why Linux?

Linux is used widely across many fields of computing.

**Servers & Cloud**

Most cloud infrastructure runs Linux, including systems used by major cloud providers.

**Embedded Systems**

Linux powers devices ranging from routers and IoT devices to spacecraft and autonomous systems.

**Development**

Linux provides a powerful environment for developers with built-in tools for compilers, scripting, networking, and automation.

## Popular Linux Distributions

A **Linux distribution (distro)** is a packaged operating system that includes the Linux kernel along with software and tools.

Common distributions include:

* **Ubuntu** – Beginner-friendly and widely used in cloud environments
* **Debian** – Extremely stable and common on servers
* **Arch Linux** – Minimal system where users configure everything manually


---

## Linux System Concept

Linux systems can be thought of as layers.

| Layer | Description |
|-------|-------------|
| Hardware | Physical machine (CPU, RAM, Disk) |
| Kernel | Core component that manages hardware and processes |
| Shell | Command-line interface used to interact with the system |
| Applications | Programs such as browsers, editors, and servers |

The most common shell on Linux is **Bash**.

Other shells also exist. For example:

* **PowerShell** is commonly used on Windows
* **Zsh** is the default shell on modern macOS

Both can also be installed on Linux.


---

# Installation & Setup

For this guide we will use **Linux Mint 22.3**.

## Recommended: Virtual Machine

Running Linux in a virtual machine allows experimentation without affecting your main operating system.

Recommended tool:

* VirtualBox

Suggested VM configuration:

* 2 CPU cores
* 4 GB RAM
* 25 GB storage

Download the Ubuntu ISO:

<https://ubuntu.com/download/desktop>

Linux Mint ISO: @[https://mirror.csclub.uwaterloo.ca/linuxmint/stable/22.3/linuxmint-22.3-cinnamon-64bit.iso](mention://6eca6ec7-7beb-4665-913c-e410b39de23a/url/bb360dc2-1120-438d-9867-32e2e298b3c3) 

See the following guide to find out how to setup a Ubuntu virtual machine on your computer: @[https://ubuntu.com/tutorials/how-to-run-ubuntu-desktop-on-a-virtual-machine-using-virtualbox#1-overview](mention://f91984f1-f16f-4647-b59a-98e84c62b275/url/e5947a92-e73f-4771-b9ce-695f5c4b6dd3)

## Alternative Options

### Windows: WSL (Windows Subsystem for Linux)

For Windows users who want Linux integration without a VM:


1. Open PowerShell as Admin.
2. Run: `wsl --install`.
3. Restart your computer.

This provides a *headless* Linux distribution, headless meaning without a GUI, terminal only (though WSL2 can actually display GUI for programs). This lets you have your own Linux distribution easily from Windows.

See the following guide for more information: @[https://learn.microsoft.com/en-us/windows/wsl/install](mention://c0391fb8-e0cb-4dc1-aada-083115e364fe/url/d502d8f4-3226-4e82-8b3d-2d55662908c6)

### Try Linux in the Browser

If you cannot install Linux locally:

* <https://distrosea.com> (test drive Linux distributions with GUI)

These allow you to test Linux environments online.

## Bare Metal

Of course, it's also possible to install Linux on your machine, but that won't be required for the guide. There's also the option of dual-booting, where you have multiple operating systems on your machine. 


---

## Desktop Environments

A **desktop environment** provides the graphical interface for Linux.

Ubuntu uses **GNOME** by default, but other environments exist. For example, [Kubuntu](https://kubuntu.org/) is a *flavor* of Ubuntu which comes with **KDE Plasma** instead.

Examples:

* **GNOME** – modern and simple

[https://upload.wikimedia.org/wikipedia/commons/9/97/GNOME%5FShell.png](https://upload.wikimedia.org/wikipedia/commons/9/97/GNOME%5FShell.png)

* **KDE Plasma** – highly customizable

[https://upload.wikimedia.org/wikipedia/commons/1/15/KDE%5FPlasma%5F6.4.5%5FLight.png](https://upload.wikimedia.org/wikipedia/commons/1/15/KDE%5FPlasma%5F6.4.5%5FLight.png)


---

# The Linux File System

The Linux filesystem is organized as a **tree structure** starting at the root directory.

```
/
```

[https://cdn.staropstech.com/starops/Blogs/File%20Systems/1.png](https://cdn.staropstech.com/starops/Blogs/File%20Systems/1.png)

Everything on the system exists somewhere under this root.

| Directory | Purpose |
|-----------|---------|
| `/`       | Root directory |
| `/home`   | User home directories |
| `/bin`    | Essential command binaries |
| `/usr/bin` | Most installed programs |
| `/etc`    | System configuration files |
| `/var`    | Logs and variable data |
| `/tmp`    | Temporary files |
| `/dev`    | Device files |
| `/proc`   | Kernel and process information |

Files that start with a `.` are hidden by default and may require a flag to view them.


---

# Absolute vs Relative Paths

Files can be referenced in two ways.

## Absolute Path

Starts from the root `/`.

Example:

```
/home/user/projects/app
```

## Relative Path

Starts from your current directory.

Example:

```
cd projects/app
```

Useful shortcuts:

| **Shortcut** | **Description** |
|----------|-------------|
| `.`      | The directory you are currently in. |
| `..`     | The directory one level above (Parent). |
| `~`      | Your specific user's home folder (`/home/username`). |
| `-`      | The *previous* directory you were just in (like a 'Back' button). |

Examples:

```bash
cd ..
cd ~/projects
```


---

## Symbolic Links

A **symbolic link (symlink)** is a special file that acts like a **shortcut** to another file or directory.

Instead of containing data itself, it points to another location in the filesystem.

Create a symbolic link with:

```bash
ln -s /home/user/projects/app app-link
```

This creates `app-link` that points to:

```
/home/user/projects/app
```

You can now access the same location using either path:

```bash
cd app-link
```

### Viewing Symbolic Links

Use `ls -l` to see links.

Example:

```
lrwxrwxrwx 1 user user 21 Mar 8 app-link -> /home/user/projects/app
```

The first character shows the file type:

| Symbol | Meaning |
|--------|---------|
| `l`    | Symbolic link |

The arrow shows where the link points.

#### Notes

* Removing a symlink **does not delete the original file**.
* Symlinks can point to **files or directories**.

Example:

```bash
ln -s /var/log logs
cd logs
```

This creates a shortcut to the system log directory.


---

# Getting Started with the Terminal

The terminal allows you to interact directly with the operating system.

You can open the terminal with:

```
Ctrl + Alt + T
```

You can also search it up or click on the shortcut on the panel.


---

## Essential Terminal Commands

| Command | Description |
|---------|-------------|
| `pwd`   | Print current directory |
| `ls`    | List files  |
| `ls -la` | Show all files including hidden |
| `cd`    | Change directory |
| `mkdir` | Create directory |
| `sudo`  | Run command as root user (admin). |

Example:

```bash
mkdir project
cd project
```


---

## Terminal Shortcuts

These shortcuts make working in the terminal much faster.

| Shortcut | Action |
|----------|--------|
| `Tab`    | Autocomplete commands/files. Press `tab` twice to view ALL options. |
| `Ctrl + C` | Stop a running command |
| `Ctrl + L` | Clear terminal |
| `↑ / ↓`  | Browse command history |
| `Ctrl + R` | Search command history |


---

## Getting Help

Linux provides built-in documentation for most commands.

### Manual Pages (`man`)

You can view detailed documentation using the `man` (manual) command.

Example:

```bash
man ls
```

Other examples:

```bash
man grep
man chmod
```

Manual pages often include:

* Description of the command
* Available options and flags
* Usage examples

Press `q` to exit the manual viewer.


---

### Quick Command Descriptions (`whatis`)

If you just want a **short description** of a command, use `whatis`.

Example:

```bash
whatis ls
```

Output:

```
ls (1) - list directory contents
```

### Searching Manual Pages (`apropos`)

You can search for commands related to a keyword using `apropos`.

Example:

```bash
apropos network
```

This searches the manual page database for commands related to **networking**.


---

## Command Help Flags

Many commands also provide help using the `--help` flag.

Example:

```bash
ls --help
```

This displays a quick overview of available options for the command.


---

# File Operations

Linux provides simple commands to manipulate files.

| Command | Purpose |
|---------|---------|
| `touch file.txt` | Create empty file |
| `cp file1 file2` | Copy file |
| `mv file1 file2` | Move or rename |
| `rm file.txt` | Delete file |
| `rm -r folder` | Delete directory (`-r` flag means recursive) |


:::warning
`rm` permanently deletes files. There is no recycle bin. Be careful with `-r` recursive flag especially.

:::


---

## Viewing Files

Useful commands for viewing file contents.

```bash
cat file.txt
```

Displays the entire file.

```bash
head -n 5 file.txt
```

Shows the first few lines.

```bash
less file.txt
```

Scrollable viewer.

Press `q` to exit.


---

## Editing Files

A simple terminal editor is **nano**.

```bash
nano notes.txt
```

Save file:

```
Ctrl + O
```

Exit:

```
Ctrl + X
```


:::tip
While **nano** is good, **vim** is better for editing files from the terminal. It's more complicated, however.

:::


---

# File Permissions

Linux is a **multi-user system**, meaning multiple users can exist on the same machine. Because of this, every file and directory has permissions that control **who can read, modify, or execute it**.

You can view permissions using:

```bash
ls -l
```

Example output:

```bash
-rwxr-xr-- 1 user user 1200 Mar 8 script.sh
```

The first column represents the **file type and permissions**.

Example:

```
-rwxr-xr--
```


---

## Permission Breakdown

Permissions are divided into four parts:

```
[TYPE][USER][GROUP][OTHER]

- rwx r-x r--
```

### File Type

The first character indicates the type of file.

| Symbol | Meaning |
|--------|---------|
| `-`    | Regular file |
| `d`    | Directory |
| `l`    | Symbolic link |

Example:

```
-rwxr-xr--
```

The `-` means this is a **regular file**.


---

### Permission Groups

The remaining characters are divided into three groups:

```
rwx   r-x   r--
│     │     │
│     │     └── Others
│     └──────── Group
└────────────── User (Owner)
```

| Group | Who it represents |
|-------|-------------------|
| User  | The file owner    |
| Group | Users in the file's group |
| Others | Everyone else     |


---

### Permission Symbols

Each group has three possible permissions.

| Symbol | Meaning |
|--------|---------|
| `r`    | Read    |
| `w`    | Write   |
| `x`    | Execute |
| `-`    | Permission not granted |

### What They Mean

For **files**:

| Permission | Effect |
|------------|--------|
| Read (`r`) | View file contents |
| Write (`w`) | Modify or overwrite the file |
| Execute (`x`) | Run the file as a program or script |

For **directories**:

| Permission | Effect |
|------------|--------|
| Read       | List directory contents |
| Write      | Modify directory entries |
| Execute    | Enter the directory and access items by name |

Creating, deleting, or renaming files in a directory usually requires **both write and execute** on that directory.


---

### Example Explained

Consider the example:

```
-rwxr-xr--
```

Breakdown:

| Group | Permissions | Meaning |
|-------|-------------|---------|
| User  | `rwx`       | Owner can read, modify, and execute |
| Group | `r-x`       | Group members can read and execute |
| Others | `r--`       | Everyone else can only read |

So for this file:

* The **owner** can edit and run the script.
* The **group** can run the script but cannot modify it.
* **Others** can only view the file.


---

## Changing Permissions

Permissions can be modified using the `chmod` command.

Example:

```bash
chmod +x script.sh
```

This adds **execute permission**.

You can also remove permissions:

```bash
chmod -x script.sh
```

Or modify specific groups:

```bash
chmod u+x script.sh
```

| Symbol | Meaning |
|--------|---------|
| `u`    | User (owner) |
| `g`    | Group   |
| `o`    | Others  |
| `a`    | All     |

Examples:

```bash
chmod g+w file.txt
```

Adds write permission for the group.

```bash
chmod o-r file.txt
```

Removes read permission from others.


---

## Numeric Permissions

Permissions can also be set using **numeric (octal) values**.

Each permission corresponds to a number:

| Permission | Value |
|------------|-------|
| Read       | 4     |
| Write      | 2     |
| Execute    | 1     |

These values are **added together**.

Examples:

| Permissions | Calculation | Value |
|-------------|-------------|-------|
| `rwx`       | 4+2+1       | 7     |
| `rw-`       | 4+2         | 6     |
| `r-x`       | 4+1         | 5     |
| `r--`       | 4           | 4     |


---

## Example: `chmod 755`

```bash
chmod 755 script.sh
```

Breakdown:

```
7 5 5
│ │ │
│ │ └── Others
│ └──── Group
└────── User
```

| Group | Value | Permissions |
|-------|-------|-------------|
| User  | 7     | `rwx`       |
| Group | 5     | `r-x`       |
| Others | 5     | `r-x`       |

So the result is:

```
-rwxr-xr-x
```

Meaning:

* Owner can read, write, and execute.
* Everyone else can read and execute.

This is **commonly used for scripts and programs**.


---

## Common Permission Patterns

| Permission | Use Case |
|------------|----------|
| `644`      | Normal files |
| `755`      | Executable scripts/programs |
| `700`      | Private files |
| `600`      | Sensitive files (SSH keys, secrets) |

Examples:

```bash
chmod 644 file.txt
chmod 755 script.sh
chmod 600 secret.txt
```


---

## Changing Ownership

Files also have an **owner and group**.

You can change them with `chown`.

Example:

```bash
sudo chown user:group file.txt
```

Example:

```bash
sudo chown alice:developers project.sh
```


---

### Tip

You can recursively modify permissions for an entire directory:

```bash
chmod -R 755 project/
```

:::warning
Avoid using `chmod -R 755` on an entire project unless you really want **every file** to be executable.
Directories and regular files often need different permissions.

:::

A common pattern is:

* Directories: `755`
* Regular files: `644`
* Scripts or programs that should run: `755`


---

# Pipes & Redirection

One of Linux's most powerful features is the ability to **combine commands together**. This works because programs communicate using standard data streams.


---

## Standard Streams

Linux programs typically interact with three standard data streams.

| Stream | Name | Description |
|--------|------|-------------|
| `stdin` | Standard Input | Data a program receives |
| `stdout` | Standard Output | Normal output from a program |
| `stderr` | Standard Error | Error messages |

By default:

* **stdin** → keyboard input
* **stdout** → terminal screen
* **stderr** → terminal screen

A useful mental model is:

* A command **reads** from `stdin`
* A command writes normal results to `stdout`
* A command writes problems to `stderr`

Even though `stdout` and `stderr` often both appear on your screen, they are **different streams**.
That difference matters when you redirect output or connect commands with pipes.


---

## Redirection

Redirection changes **where a stream goes**.

### Redirect `stdout` (`>`)

```bash
echo "Hello" > file.txt
```

This sends the command's **stdout** to `file.txt`.

If the file already exists, it will be **overwritten**.


---

### Append `stdout` (`>>`)

```bash
echo "World" >> file.txt
```

This **adds text to the end of the file** instead of replacing it.


---

### Redirect `stdin` (`<`)

You can also send a file into a command as input.

```bash
wc -l < file.txt
```

This sends the contents of `file.txt` into the command's `stdin`.


---

### Redirect `stderr` (`2>`)

Errors are written to **stderr**, which can also be redirected.

Example:

```bash
ls missingfile 2> error.log
```

This sends error messages into `error.log`.

| Symbol | Meaning |
|--------|---------|
| `>`    | Redirect stdout |
| `>>`   | Append stdout |
| `<`    | Redirect stdin |
| `2>`   | Redirect stderr |


---

### Redirect Both `stdout` and `stderr`

Sometimes you want to save **all output** from a command.

Example:

```bash
command > output.txt 2>&1
```

This sends **both stdout and stderr** into the same file.


---

### Discard Output with `/dev/null`

`/dev/null` is a special file that throws away anything sent to it.

Example:

```bash
command > /dev/null
```

This hides the command's normal output.

You can also separate normal output from errors:

```bash
command > /dev/null 2> errors.txt
```

This discards `stdout` while saving `stderr`.


---

## Pipes

A **pipe** (`|`) sends the **stdout of one command** into the **stdin of another**.

Example:

```bash
echo "one two three" | wc -w
```

Explanation:

1. `echo` writes text to `stdout`
2. `|` connects that output to the next command
3. `wc -w` reads from `stdin` and counts the words

Another example:

```bash
ls /etc | grep network
```

This works because `ls /etc` writes to `stdout`, and `grep` reads from `stdin`.

Important:

* Pipes carry **stdout**
* `stderr` still goes to the terminal unless you redirect it

More examples:

```bash
ps aux | grep python
```

Lists running processes and filters for Python.

```bash
history | grep ssh
```

Searches command history for SSH commands.

Pipes allow you to **build complex workflows using simple tools**.


---

## Combining Pipes and Redirection

Pipes and redirection are often used together.

Example:

```bash
command1 | command2 > result.txt
```

This means:

1. `command1` writes to `stdout`
2. `command2` reads that output from `stdin`
3. The final `stdout` is saved to `result.txt`

You can also separate normal output from errors:

```bash
command > output.txt 2> errors.txt
```

This saves `stdout` and `stderr` to different files.


---

## Using `tail`

The `tail` command shows the end of a file.

```bash
tail /var/log/syslog
```

By default it displays the **last 10 lines**.

### Real-Time Monitoring (`-f`)

The `-f` flag allows you to follow file updates in real time.

```bash
tail -f /var/log/syslog
```

This keeps the command running and updates whenever new lines are written.

This is commonly used for **monitoring logs while a program is running**.

Stop the command with:

```
Ctrl + C
```


---

## Return Codes (Exit Status)

Every Linux command returns a **status code** when it finishes.

| Code | Meaning |
|------|---------|
| `0`  | Success |
| Non-zero | Error occurred |

You can check the exit status of the last command using:

```bash
echo $?
```

Example:

```bash
ls file.txt
echo $?
```

If the file exists:

```
0
```

If it does not exist:

```
2
```

Exit codes are important because they allow scripts and automation tools to **detect success or failure**.


---

## Command Chaining

Because commands return exit codes, the shell can decide **whether to run another command based on success or failure**.

Two common operators are used.

| Operator | Meaning |     |
|----------|---------|-----|
| `&&`     | Run next command **only if previous command succeeds** |     |
| `\|\|`   | Run next command **only if previous command fails** |     |


---

### Run Next Command on Success (`&&`)

Example:

```bash
mkdir project && cd project
```

Explanation:


1. `mkdir project` runs first
2. If successful, `cd project` runs

If the directory creation fails, the second command will **not run**.

Another example:

```bash
sudo apt update && sudo apt upgrade
```

The upgrade runs **only if the update succeeds**.


---

### Run Next Command on Failure (`||`)

Example:

```bash
mkdir project || echo "Directory creation failed"
```

If `mkdir` fails, the message will be printed.


---

### Combining Both

You can combine both operators, but this is not always the same as a full `if/else` structure.

For example:

```bash
mkdir project && echo "Created successfully"
mkdir project || echo "Creation failed"
```

These examples mean:


1. Print the success message only if `mkdir` succeeds
2. Print the failure message only if `mkdir` fails

If you want a true success/failure branch for one command, use `if`:

```bash
if mkdir project; then
  echo "Created successfully"
else
  echo "Creation failed"
fi
```


---

### Practical Example

Suppose you want to compile a program and run it only if compilation succeeds:

```bash
gcc program.c -o program && ./program
```

This means:


1. Compile the program
2. Only run it if compilation succeeded

This pattern is very common in **development workflows and automation scripts**.


---

# Finding Files

Linux includes tools for locating files and searching inside them.

## Searching by Name with `find`

Search current directory:

```bash
find . -name "notes.txt"
```

This searches from the current directory (`.`) downward.

Search entire system:

```bash
sudo find / -name "config.json"
```


---

## Filtering Search Results

`find` can filter results in many ways.

### Filter by File Type

```bash
find . -type f
```

This finds only **regular files**.

```bash
find . -type d
```

This finds only **directories**.


---

### Filter by Size

```bash
find . -type f -size +100k
```

This finds files larger than **100 KB**.


---

### Filter by Modification Time

```bash
find . -type f -mtime -7
```

This finds files modified within the last **7 days**.


---

## Searching Inside Files with `grep`

`find` locates files by properties such as name, size, and time.
`grep` searches for **text inside files**.

Example:

```bash
grep "Hello" notes.txt
```

This prints lines in `notes.txt` that contain `Hello`.


---

## Recursive Search with `grep -r`

To search through a directory and all of its subdirectories, use `grep -r`.

```bash
grep -r "WORKSHOP_TOKEN" ~/challenges/search/data
```

This searches every file under that directory for the matching text.

Find where a command is located:

```bash
which python3
```


---

# Package Management

Ubuntu uses the **APT package manager**.

Update package list:

```bash
sudo apt update
```

Upgrade installed packages:

```bash
sudo apt upgrade
```

Install software:

```bash
sudo apt install git
```

Remove software:

```bash
sudo apt remove package_name
```


---

# Process Management

Programs running on Linux are called **processes**.

View processes:

```bash
ps aux
```

Interactive monitor:

```bash
top
```

Install improved process viewer:

```bash
sudo apt install htop
```

Stop a process:

```bash
kill <PID>
```

This sends the default termination signal (`SIGTERM`), giving the process a chance to shut down cleanly.

If a process does not respond, you can force it to stop:

```bash
kill -9 <PID>
```

:::warning
`kill -9` force-stops a process immediately. It should usually be a last resort.

:::


---

## The `/proc` Filesystem

Linux exposes process information through a special virtual filesystem called `/proc`.

Each running process has a directory named after its PID.

Example:

```bash
/proc/1234
```

Inside that directory are files containing information about the process.


---

## Reading a Process Environment

A process's environment variables are stored in:

```bash
/proc/<PID>/environ
```

Example:

```bash
cat /proc/1234/environ
```

This file is usually **null-separated**, so the output may look hard to read.

To make it readable, convert null characters into new lines:

```bash
tr '\0' '\n' < /proc/1234/environ
```

You can then filter the result:

```bash
tr '\0' '\n' < /proc/1234/environ | grep SECRET
```

This is useful when you need to inspect the environment of a running process.


---

# Environment Variables & PATH

Environment variables store system configuration.

View all variables:

```bash
printenv
```

View specific variable:

```bash
echo $PATH
```

## What is PATH?

The `PATH` environment variable tells Linux **where to search for executable programs** when you type a command.

Think of PATH as a **list of folders**.

When you run a command like:

```bash
ls
```

Linux does **not** search the entire filesystem.

Instead, it checks each directory listed in `PATH`, in order, until it finds the executable.


---

## Viewing PATH

You can see your PATH value using:

```bash
echo $PATH
```

Example output:

```
/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

Notice the `:` separator.

This means PATH is a list of directories such as:

* `/usr/local/bin`
* `/usr/bin`
* `/bin`
* `/usr/sbin`
* `/sbin`

Linux will check these directories whenever you run a command.


---

## Simple Mental Model

Imagine PATH like this:

```
When you type a command:

→ Look inside PATH folder #1
→ If not found, check folder #2
→ Continue searching
→ If still not found → "command not found"
```

This is why you sometimes see:

```
command not found
```

It means Linux could not find the program inside your PATH directories.


---

## Adding a Directory to PATH

If you have scripts or programs you want to run from anywhere, you can add their folder to PATH.

Example:

```bash
export PATH=$PATH:/home/user/scripts
```

This means:


1. Take the current PATH value (`$PATH`)
2. Add `:/home/user/scripts` to the end


:::warning
Do not overwrite PATH completely unless you know what you are doing. 

:::

Correct pattern:

```bash
export PATH=$PATH:/new/directory
```


---

## Making PATH Changes Permanent

If you want PATH changes to persist after restarting the terminal, add the export command to your shell configuration.

Edit your bash configuration:

```bash
nano ~/.bashrc
```

Add this line at the end:

```bash
export PATH=$PATH:/home/user/scripts
```

Then apply changes:

```bash
source ~/.bashrc
```


---

## Aliases in `~/.bashrc`

An **alias** is a shortcut name for a command.

Example:

```bash
alias hello='echo "Hello, Linux!"'
```

Now running:

```bash
hello
```

Will execute:

```bash
echo "Hello, Linux!"
```

If you want the alias to persist, add it to `~/.bashrc` and reload the file:

```bash
source ~/.bashrc
```


---

## Practical Example

Suppose you create a script:

```bash
/home/user/scripts/myscript
```

If you add:

```bash
export PATH=$PATH:/home/user/scripts
```

You can now run:

```bash
myscript
```

From anywhere in the terminal.

Without PATH modification, you would need to run:

```bash
/home/user/scripts/myscript
```


---

## Why PATH Matters

PATH is heavily used in development because it allows you to:

* Run compilers
* Run build tools
* Run custom automation scripts
* Use installed software globally

You can check where a command lives using:

```bash
which python3
```

This shows the executable location.


---

## Quick Tip

If something is installed but the command does not work:

Check:


1. Is it installed?
2. Is it inside PATH?


---

# Bash Scripting

Linux allows you to automate tasks using **shell scripts** — text files containing commands that the system executes in order.

### Shebang (`#!`) — Specifying the Interpreter

At the very top of a script, you often include a **shebang**:

```bash
#!/bin/bash
```

* This tells the system **which program should run the script**.
* Without it, you'd have to explicitly run the script with the interpreter:

```bash
bash setup.sh
```

With a shebang and executable permission, you can run the script directly:

```bash
chmod +x setup.sh
./setup.sh
```

You can also use `/usr/bin/env` to make your script more **portable**:

```bash
#!/usr/bin/env bash
```

* This finds Bash wherever it is installed, which is useful across different Linux distributions.


---

### Example Script

Create a script called `setup.sh`:

```bash
#!/bin/bash

echo "Setting up project..."

mkdir src
mkdir docs
mkdir assets

echo "Project structure created!"
```

Make it executable:

```bash
chmod +x setup.sh
```

Run it:

```bash
./setup.sh
```

Your directories will be created, and the messages printed in the terminal.


---

### Script Arguments (`$1`, `$2`, etc.)

Shell scripts can accept values from the command line.
These are called **positional parameters**.

| Variable | Meaning |
|----------|---------|
| `$1`     | First argument |
| `$2`     | Second argument |
| `$3`     | Third argument |

Example:

```bash
#!/bin/bash
echo "Hello, $1! Welcome to the workshop."
```

If the script is run like this:

```bash
./greet.sh Alice
```

The output will be:

```bash
Hello, Alice! Welcome to the workshop.
```

Using double quotes is important when mixing text with variables.


---

### Adding Scripts to PATH

You can add the folder containing your script to your `PATH` in `.bashrc` to run it from anywhere:

```bash
export PATH=$PATH:/home/user/scripts
```

Then simply run:

```bash
setup.sh
```


---

### Tip

* Always include a shebang for scripts you plan to share or reuse.
* It ensures the **correct interpreter** is used, avoids errors, and makes your script **portable**.


---

# Remote Access with SSH

Linux systems can be accessed remotely using SSH.

SSH is provided by:

OpenSSH. You may need to install some packages.

Example connection:

```bash
ssh username@server_ip
```

Example:

```bash
ssh ubuntu@192.168.1.20
```

SSH is commonly used to manage servers and cloud machines.


---

# Development Workflow Example

A typical developer workflow might look like this:

```bash
cd ~/projects

git clone https://github.com/example/repo.git
cd repo

python3 --version

chmod +x build.sh
./build.sh
```

Install development tools:

```bash
sudo apt install build-essential
```

This installs a standard development toolchain on Ubuntu, including GCC, `make`, and other tools commonly used to build software.


---

# Basic Networking Tools

Linux includes many built-in tools for inspecting and troubleshooting networks. These are extremely useful when working with servers, APIs, or cloud infrastructure.


---

## Viewing Network Interfaces

You can view your system's network interfaces and IP addresses using:

```bash
ip a
```

This shows information about all network interfaces on your system, including:

* IP addresses
* network interfaces (e.g., `eth0` - ethernet, `wlan0` - WiFi)
* connection state

Example output snippet:

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>
    inet 192.168.1.25/24
```

This indicates the system has the IP address:

```
192.168.1.25
```


---

## Testing Connectivity with `ping`

The `ping` command checks if a host is reachable over the network.

Example:

```bash
ping google.com
```

This sends packets to the host and reports how long it takes to receive a response.

Example output:

```
64 bytes from google.com: icmp_seq=1 ttl=118 time=18 ms
```

Stop `ping` with:

```
Ctrl + C
```


---

## Fetching Data from the Internet with `curl`

`curl` is a powerful tool used to transfer data from servers. It is commonly used for testing APIs.

Example:

```bash
curl https://example.com
```

This retrieves the HTML of a webpage.

You can also request data from APIs:

```bash
curl https://api.github.com
```

This returns structured data (JSON) from GitHub's public API.


---

## Checking Open Connections

To see active network connections, you can use:

```bash
ss -tuln
```

This shows listening network ports and active connections.

Common columns include:

| Column | Meaning |
|--------|---------|
| Local Address | Address on your system |
| Port   | Network port |
| State  | Connection status |

Example:

```
tcp LISTEN 0 128 0.0.0.0:22
```

This indicates that **SSH is listening on port 22**.


---

## Checking DNS Resolution

You can test domain name resolution using:

```bash
nslookup google.com
```

This shows the IP address associated with the domain.

Example output:

```
Name: google.com
Address: 142.250.72.14
```

This demonstrates how domain names are translated into IP addresses.


---

## Downloading Files

You can download files directly from the internet using `curl`.

Example:

```bash
curl -O https://example.com/file.txt
```

The `-O` flag saves the file using its original name.


---

## Example Workflow

A developer troubleshooting a server might run:

```bash
ping example.com
curl https://example.com
ss -tuln
```

These commands help determine:

* if a host is reachable
* if a service is responding
* what ports are open


---

# Practice Exercises

Try these exercises on your Linux system.


---

## Level 1 — Basic Navigation (Beginner)

These help you become comfortable with the terminal.

### 1. Directory Exploration

Navigate to the following directory:

```bash
cd /var/log
```

Then list all files:

```bash
ls -la
```

Try answering:

* What files exist inside `/var/log`?
* Can you identify log files?


---

### 2. Read a System Log File

Try reading the system log:

```bash
sudo cat /var/log/syslog
```

If the file is large, try:

```bash
sudo head -n 20 /var/log/syslog
```


---

### 3. Find Compression Tools

Run:

```bash
ls /bin | grep zip
```

:::warning
This only checks `/bin`, not every directory in your `PATH`.
A command may be installed in `/usr/bin` or another location.

:::

This is still a useful exercise for practicing pipes and filtering.

If you want to search for matching commands across your shell environment, try:

```bash
compgen -c | grep zip
```

If you want to see where a specific command lives, use:

```bash
which unzip
```

Question:

* What tools related to file compression are installed?


---

## Level 2 — Linux Tool Practice (Intermediate)

These exercises use pipes and searching.


---

### 4. Count Files in a Directory

Try:

```bash
ls /usr/bin | wc -l
```

:::warning
This counts entries in `/usr/bin`. It does not precisely count all installed programs on the system.

:::

It is still a useful exercise for practicing pipes and counting.

Question:

* How many entries are in `/usr/bin`?


---

### 5. Search Command History

Try searching for SSH commands (or any other command) you previously ran:

```bash
history | grep ssh
```

If nothing appears, run a few commands first.


---

### 6. Check Network Connectivity

Test if you can reach a website:

```bash
ping google.com
```

Stop the command using:

```
Ctrl + C
```


---

### 7. Fetch Web Data

Try:

```bash
curl https://example.com
```

Optional challenge:

* Can you filter the output using `grep`?

Example:

```bash
curl -s https://example.com | grep html
```


---

## Level 3 — Mini Developer Challenge


---

### Project Structure Automation

Create a script called `setup.sh` that does the following:


1. Creates these directories:

```
assets
docs
src
```


2. Prints a message saying project setup is complete.
3. Make the script executable.
4. Add the script folder to your PATH.
5. Run the script from any directory.


---

### Bonus Challenge

Try writing a script that:

* Asks the user for their name
* Prints a greeting message

Hint: You can use `read name` to ask for input from a user and store it in a variable. Here, `name` is just the variable name you choose.

Example:

```bash
read name
echo "Hello, $name"
```


---


---

# Common Troubleshooting

## Command Not Found

If you see:

```
command not found
```

Check the following:


1. Is the program installed?

Try:

```bash
which program_name
```

Example:

```bash
which python3
```

If nothing is returned, the program may not be installed or is not in your PATH.


2. Check installation:

:::warning
Package names do not always match command names exactly.
Also, `which` only checks whether a command can be found in your `PATH`.

:::

If you need to search for the correct package, use:

```bash
apt search program_name
```

Example:

```bash
apt search python3
```

After you identify the correct package name, install it with:

```bash
sudo apt install package_name
```


---

## Permission Denied

If you see:

```
Permission denied
```

Possible causes:

* You are trying to modify a protected file
* The file does not have execute permission

Solutions:

### Use sudo (if appropriate)

```bash
sudo command_here
```

Example:

```bash
sudo nano /etc/sysctl.conf
```


:::warning
Use `sudo` carefully since it gives administrator privileges.

:::


---

## Locked Package Manager

If you see errors like:

```
Could not get lock /var/lib/dpkg/lock
```

It usually means another update process is running.

Fixes:

* Wait a minute and try again.
* Close other update windows.

Avoid forcing locks unless necessary.


---

## Script Cannot Run

If your script does not run:

Check permissions:

```bash
ls -l script.sh
```

If execute permission is missing:

```bash
chmod +x script.sh
```

Then run:

```bash
./script.sh
```

Remember:

* Scripts need execute permission unless run explicitly with an interpreter.

Example:

```bash
bash script.sh
```


---

## Network Issues

If networking commands fail:

Check connectivity:

```bash
ping google.com
```

Check interface status:

```bash
ip a
```

Check DNS resolution:

```bash
nslookup google.com
```

If DNS fails but IP ping works, it is likely a DNS configuration problem.


---

## APT Update Problems

If package installation fails:

Run:

```bash
sudo apt update
sudo apt upgrade
```

If installation is still failing, check internet connectivity.


---

## When in Doubt

Use built-in help tools:

```bash
man command_name
```

or

```bash
command_name --help
```
