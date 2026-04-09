#!/usr/bin/env python3
"""
Agent email reporter.
Usage: echo "report content" | python send-report.py "Subject"
   or: python send-report.py "Subject" report_content.txt
"""
import sys
import os
import smtplib
import argparse
from email.mime.text import MIMEText
from datetime import datetime

def send_report(subject: str, body: str, to_addr: str, from_addr: str, smtp_host: str, smtp_port: int):
    msg = MIMEText(body, 'plain', 'utf-8')
    msg['Subject'] = f"[Agent] {subject} – {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    msg['From'] = from_addr
    msg['To'] = to_addr

    try:
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.send_message(msg)
        print(f"[report] Sent: {msg['Subject']}")
    except Exception as e:
        print(f"[report] ERROR: Failed to send email: {e}", file=sys.stderr)
        # Don't fail hard – agent continues even if email fails
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('subject', help='Email subject')
    parser.add_argument('file', nargs='?', help='File with report body (or stdin)')
    args = parser.parse_args()

    # Read body from file or stdin
    if args.file and os.path.exists(args.file):
        with open(args.file) as f:
            body = f.read()
    else:
        body = sys.stdin.read()

    # Get config from environment
    to_addr = os.environ.get('AGENT_REPORT_EMAIL', '')
    from_addr = os.environ.get('AGENT_FROM_EMAIL', 'agent@localhost')
    smtp_host = os.environ.get('SMTP_HOST', 'localhost')
    smtp_port = int(os.environ.get('SMTP_PORT', '25'))

    if not to_addr:
        print(f"[report] AGENT_REPORT_EMAIL not set. Would have sent:\nSubject: {args.subject}\n\n{body}")
        return

    send_report(args.subject, body, to_addr, from_addr, smtp_host, smtp_port)

if __name__ == '__main__':
    main()
