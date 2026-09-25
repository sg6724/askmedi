# Live end-to-end tests

`live_e2e_test.dart` drives the app's **real** repositories (not fakes) against the deployed
services: Supabase Auth and Postgres, the Vercel backend, Gemini/Groq, ElevenLabs and
OpenStreetMap. It signs in, completes onboarding, then runs chat (emergency and a full follow-up
conversation), medicine scan and lookup, report parse/confirm/trend, hospital search, voice and
history, and finally deletes the account.

It lives outside `test/` because it needs the network and a throwaway account, so the normal
`flutter test` run (and CI) never touches it.

```sh
flutter test test_live --dart-define-from-file=env/dev.json \
  --dart-define=E2E_EMAIL=<confirmed throwaway user> --dart-define=E2E_PASSWORD=<its password> \
  --dart-define=E2E_LAB_PDF=<path to a lab report PDF> \
  --dart-define=E2E_STRIP_IMAGE=<path to a medicine strip photo>   # optional
```

The account must already exist and be confirmed. The last step deletes it with all its data.
