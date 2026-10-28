# Privacy

The privacy documentation lives on the docs site, so there is one version to keep in sync with the code:
**<https://triplibre.hhtdiary.org/docs/privacy.html>** (source: [`docs/privacy.html`](docs/privacy.html)).

It covers what is stored and where, every case in which the app uses the network, exactly what an export contains
(including the full `travel.sqlite` snapshot), erase and deletion, re-identification risk, and how to verify each
statement in the code.

Summary: no account, no server, no analytics SDK, no sync. Location data stays on the iPhone unless you export it.
The only network requests are optional address lookup (off by default, Apple's geocoder), map tiles (Apple Maps) and
an on-request download of the public airport list.
