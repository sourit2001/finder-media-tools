# Windows portable 0.3.0

Adds Unlock this PC and Restore purchase; registers the per-user payment callback before opening checkout independently of Explorer menu settings. Pending checkout is saved before browser launch and reused rather than creating duplicate purchases. Activation updates the open window. Existing video compression and audio functionality retained.

Server validates platform and installation ownership, routes callbacks from stored checkout records, preserves activation tokens on retry, and prevents paid notifications from restoring refunded licenses. Refund/dispute reconciliation supports transaction IDs and resolves legacy order mappings through Creem.

Payment flow is tested with a local SQLite database, real signed-webhook handling and a mocked provider. Real money checkout/activation must be accepted on a Windows PC by the purchaser. Windows code is unsigned; HDR is not supported.
