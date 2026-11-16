# Security policy

## Supported versions

Only the latest release gets fixes. Upgrade before reporting a problem.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through
GitHub instead: open the repository's **Security** tab and choose **Report a vulnerability**.
Include the widget version, your Plasma version, and steps to reproduce.

You should get a reply within a week. Once a fix is released, the report is published as
a security advisory with credit to you, unless you'd rather stay anonymous.

## Known limitations

These are known and documented, so they aren't treated as vulnerabilities:

- Without `secret-tool` or a Secret Service such as KWallet, Plasma stores the broker
  password in plain text in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, and the
  widget passes it to `mosquitto_sub` on the command line, where other users on the same
  machine can see it in the process list.
- With a wallet, the password is still on a command line briefly: while a new one is
  saved, and while Test Connection or Find Cars tries one that hasn't been applied. One
  longer than 1000 bytes is on `mosquitto_sub`'s command line at every poll.
- Removing the widget leaves its secrets in the wallet.

Use a broker account that can only read TeslaMate's topics, and deny it the car's
position topics. See [Security and privacy](README.md#security-and-privacy) in the README.
