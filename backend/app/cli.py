"""Bootstrap CLI. Usage: python -m app.cli create-admin --phone +91XXXXXXXXXX --name "Name"
Password is read from the ADMIN_PASSWORD env var or prompted; never passed on the command line."""
import argparse
import getpass
import os
import sys

from sqlalchemy import select

from .db import get_db
from .models import Role, User
from .security import hash_password


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("create-admin")
    a.add_argument("--phone", required=True)
    a.add_argument("--name", required=True)
    args = p.parse_args(argv)
    pw = os.environ.get("ADMIN_PASSWORD") or getpass.getpass("Admin password (min 8 chars): ")
    if len(pw) < 8:
        sys.exit("Password too short")
    db = next(get_db())
    if db.scalar(select(User).where(User.phone == args.phone)):
        sys.exit("User with that phone already exists")
    db.add(User(phone=args.phone, name=args.name, password_hash=hash_password(pw), role=Role.admin))
    db.commit()
    print("Admin created.")


if __name__ == "__main__":
    main()
