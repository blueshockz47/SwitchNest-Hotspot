# Control Center preview

Requires Python 3 and PySide6 (Qt 6). Run as the normal desktop user from the repository root:

    python3 -m v8.control_center

If PySide6 is not present, use a user-owned virtual environment:

    python3 -m venv ~/.local/share/switchnest-v8-venv
    ~/.local/share/switchnest-v8-venv/bin/pip install PySide6
    ~/.local/share/switchnest-v8-venv/bin/python -m v8.control_center

The existing v7.1 panel installer must already have installed its root-owned helper for ON/OFF actions. The application reuses that fixed helper via pkexec; it does not install new privileged components or change DNS policy. Diagnostics are read-only and may be permission limited. Filtered Internet is disabled. This preview has not been hardware tested.
