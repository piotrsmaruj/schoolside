# Bezpieczeństwo i prywatność

Schoolside działa lokalnie. Dane konta i klucz szyfrowania są przechowywane w macOS
Keychain, a dane offline w szyfrowanym pliku poza katalogiem repozytorium.
Nie ma serwera Schoolside zbierającego hasła lub dane uczniów.

## Zgłaszanie problemów

Zwykłe błędy można zgłaszać przez GitHub Issues. Do odtworzenia problemu używaj
fikcyjnych danych. Nie dołączaj loginu, hasła, cookies, tokenów sesji, eksportu
Keychain, cache aplikacji ani plików HAR z zalogowanej sesji. Usuń z opisów,
logów i zrzutów ekranu dane uczniów, rodziców, nauczycieli i szkoły.

Luki bezpieczeństwa zgłaszaj prywatnie przez zakładkę **Security → Report
a vulnerability** tego repozytorium, jeśli ta funkcja jest dostępna.
Nie publikuj aktywnych sekretów ani danych osobowych w publicznym zgłoszeniu.

## Praca z repozytorium

Testy korzystają z danych syntetycznych i nie wymagają prawdziwego konta.
Buildy, lokalne środowisko Python, cache, logi, eksporty i lokalne notatki
z pracy są wykluczone przez `.gitignore`. Przed publikacją nowych plików
sprawdź także ich treść — samo `.gitignore` nie anonimizuje danych.

Nie publikuj zbudowanego lokalnie bundle jako samodzielnego instalatora:
obecnie zawiera on ścieżkę do projektu i wymaga lokalnego środowiska Python.
