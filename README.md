killbill-chartmogul-plugin
==========================

Plugin to mirror Kill Bill data into ChartMogul.

Release builds are available on [Maven Central](http://search.maven.org/#search%7Cga%7C1%7Cg%3A%22org.kill-bill.billing.plugin.ruby%22%20AND%20a%3A%22chartmogul-plugin%22) with coordinates `org.kill-bill.billing.plugin.ruby:chartmogul-plugin`.

Kill Bill compatibility
-----------------------

| Plugin version | Kill Bill version |
| -------------: | ----------------: |
| 0.0.y          | 0.17.z            |

Configuration
-------------

```
curl -v \
     -X POST \
     -u admin:password \
     -H 'X-Killbill-ApiKey: bob' \
     -H 'X-Killbill-ApiSecret: lazar' \
     -H 'X-Killbill-CreatedBy: admin' \
     -H 'Content-Type: text/plain' \
     -d ':chartmogul:
  :account_token: 'account_token'
  :secret_key: 'secret_key'' \
     http://127.0.0.1:8080/1.0/kb/tenants/uploadPluginConfig/killbill-chartmogul
```

Your Account Token and Secret Key are available from the administration section of your ChartMogul account.

Usage
-----

The plugin will automatically listen to all events, and create or update the associated data in ChartMogul.
