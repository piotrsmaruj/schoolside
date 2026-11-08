# Schoolside

**Nieoficjalny klient dla LIBRUS Synergia na macOS.**

Schoolside to niezależny projekt, niepowiązany z firmą LIBRUS i przez nią
niezatwierdzony. Nazwa LIBRUS Synergia identyfikuje wyłącznie usługę, z którą
aplikacja współpracuje. Projekt nie używa logo ani materiałów graficznych LIBRUS.

Natywny panel SwiftUI dla jednego ucznia i numerycznego konta rodzica. Dane pobiera
lokalny moduł Python przez nieoficjalną bibliotekę `librus-synergia`.

## Funkcje

- Dzisiaj/Jutro: aktualna i następna lekcja, koniec zajęć, najbliższe wydarzenie
  z opisem, plan dnia, ostatnie oceny oraz zadania na jutro.
- Co nowego: nieprzejrzane oceny, wiadomości, wydarzenia, zadania, ogłoszenia
  i zmiany nadchodzącego planu; oznaczenia zachowane po pobraniu i restarcie.
- Tabela planu: dni w kolumnach i godziny w wierszach, bieżący/następny tydzień,
  zastępstwa i odwołane lekcje, etykiety „Teraz”/„Zakończona” i nieprzejrzane zmiany.
  Przy jednoznacznym porównaniu widać poprzednią i nową salę/godzinę.
  Nagłówki dni pozostają widoczne przy przewijaniu.
- Oceny standardowe oraz punktowe/procentowe: procent i zdobyte/maksymalne punkty.
  Widoki Ostatnie/Przedmioty, rozwijana historia i filtry semestru/rodzaju pracy.
  Średnia procentowa przy każdym przedmiocie, zgodna z filtrami.
  Domyślnie otwiera się widok Przedmioty ze średnimi.
  Przy nieznanym maksimum pokazujemy punkty, bez zgadywania procentu.
- 50 ostatnich wiadomości: lista obok pełnej treści, filtry Wszystkie/Nieprzeczytane/
  Z załącznikami, pobieranie plików. Pełna treść pobierana wyłącznie po kliknięciu.
- Terminarz, frekwencja, zadania z załącznikami i ogłoszenia.
- Organizer „Do ogarnięcia”: automatycznie pobrane zadania domowe, własne zadania,
  notatki, terminy, odhaczanie i opcjonalne przypomnienia macOS.
  Wiadomość lub wydarzenie można powiązać z zadaniem przyciskiem „Dodaj do ogarnięcia”.
- „Najbliższe 7 dni”: wspólny widok wydarzeń szkolnych i zadań, liczniki przy dniach,
  zaległe sprawy i zadania bez terminu. Przy wydarzeniu można zaplanować przygotowanie.
- Podgląd w pasku menu, wyszukiwanie w zakładce, ręczne odświeżanie.
- Synchronizacja co 15 minut oraz po wybudzeniu, jeśli dane są starsze.
- Termin następnego odświeżenia widoczny na dole panelu i w pasku menu.
- Szyfrowane dane offline. Po awarii modułu pozostają ostatnie poprawne dane.
- Opcjonalne powiadomienia macOS, domyślnie wyłączone. Bez telefonu.
- Motyw jasny, ciemny lub zgodny z systemem (Auto), zapamiętywany na tym Macu.
- Paleta: ciepłe neutralne tło, grafit, białe karty i przygaszony śliwkowy akcent;
  adaptacyjne odpowiedniki dla ciemnego motywu i zwiększonego kontrastu.
- Zwarte listy i zapamiętywany wybór widoku Kompaktowy/Wygodny.
- Ustawienia pod przyciskiem ⚙︎: wygląd, powiadomienia i konto; skrót ⌘,.

## Uruchomienie

Wymagania: Apple Silicon, macOS 14+, Command Line Tools dla Xcode, Python 3.12+, uv.
Zależności są przypięte w `uv.lock`.

```bash
git clone https://github.com/piotrsmaruj/schoolside.git
cd schoolside
uv sync --locked
.venv/bin/python scripts/build_desktop.py
open build/Schoolside.app
```

Wpisz numeryczny **login rodzica** i hasło do Synergii w oknie aplikacji, następnie
kliknij **Połącz i zapamiętaj**. Pierwsze pobranie może potrwać do kilku minut.
Hasło i sesja zostaną zapisane w macOS Keychain. Kolejne uruchomienia wczytują
lokalne dane i próbują odnowić zapisaną sesję automatycznie.

Po zamknięciu okna aplikacja nadal działa w pasku menu. **Zakończ** w menu aplikacji
kończy też synchronizację. Uśpiony lub wyłączony Mac nie pobiera nowych danych.
Każde pobranie ustawia kolejny termin za 15 minut od rozpoczęcia synchronizacji.
Ręczne odświeżenie przesuwa ten termin. Jeśli wypadnie on podczas pobierania
wiadomości lub załącznika, synchronizacja ruszy zaraz po zakończeniu tej operacji.
Powiadomienia włącza przycisk w Ustawieniach; zgodę obsługuje macOS. Jeśli system
wcześniej odmówił zgody, aplikacja otwiera ustawienia powiadomień. Po zmianie zgody
wróć do Schoolside; stan aktualizuje się automatycznie. Przycisk **Test powiadomienia**
wysyła lokalny komunikat bez danych ucznia. macOS może wyciszać banery podczas
udostępniania ekranu lub w trybie skupienia.

Powiadomienia pojawiają się po synchronizacji, gdy przybędą oceny, wiadomości,
wydarzenia lub zadania albo zmieni się plan nadchodzących lekcji. Pierwsze pobranie
nie powiadamia o całej historii. Automatyczne sprawdzanie wymaga uruchomionej aplikacji.
Motyw i gęstość list wybierzesz w Ustawieniach w lewym panelu.

Semestr i rodzaj pracy pochodzą z danych Librusa. Starsze wpisy bez metadanych
pozostają dostępne pod filtrem „Brak semestru”/„Brak rodzaju”; następne poprawne
pobranie uzupełnia metadane. Brak kategorii nie blokuje pobierania samych ocen.
Średnia procentowa przedmiotu uwzględnia punkty, maksymalne punkty oraz wagę kategorii:
`100 × suma(punkty × waga) / suma(maksymalne punkty × waga)`.
To sposób liczenia z biblioteki `librus-synergia`, na pełnych danych punktowych;
zaokrąglamy dopiero wynik, do dwóch miejsc po przecinku, z połówkami w górę
(np. 47,625 → 47,63). Przy braku wagi przyjmujemy 1.
Pomijamy oceny wyłączone ze średniej w Librusie, oceny standardowe (np. 1–6)
i wpisy bez poprawnej liczby punktów lub maksimum oraz z niepoprawną lub zerową wagą.
Brak danych oznaczamy „—”. Filtry zmieniają zestaw ocen uwzględnionych w wyniku.
Po aktualizacji odśwież dane, żeby uzupełnić informacje potrzebne do średniej
w starszym cache. Najazd na średnią pokazuje liczbę uwzględnionych ocen.
Sam wybór zakładki lub filtra wiadomości nie oznacza ich jako przeczytane.
Przy szybkim przełączaniu poprzednie pobieranie jest anulowane. Już otwarte
wiadomości są ponownie wyświetlane z pamięci bieżącej sesji aplikacji.

„Co nowego” oznacza wpisy dodane od ostatnich poprawnych pobrań, których jeszcze
nie otwarto w aplikacji. Kolejne pobranie nie usuwa tych oznaczeń. Otwarcie wpisu
usuwa jego oznaczenie; pełna wiadomość musi zostać poprawnie pobrana. Przycisk
„Oznacz wszystkie jako przejrzane” zmienia tylko lokalną listę nowości, bez
oznaczania wiadomości jako przeczytane w Librusie. Pierwsze pobranie ustala bazę
i nie oznacza całej historii. Zmiany planu dotyczą dni dzisiejszego i przyszłych.
Chwilowa awaria modułu zachowuje jego ostatnie poprawne dane; po odzyskaniu
połączenia nowe wpisy nadal są wykrywane. Nowy tydzień objęty pobieraniem ustala
bazę planu i nie powoduje lawiny powiadomień. Niepełne dane są oznaczone w panelu.

## Prywatność

- Brak serwera HTTP i zewnętrznej usługi przechowującej dane.
- Login i hasło trafiają tylko do Librusa przez HTTPS; między lokalnymi procesami
  przechodzą przez prywatne potoki stdin/stdout, bez argumentów procesu i logów.
- Hasło, cookies i klucz cache znajdują się w Keychain pod usługą `local.librus.desktop`.
- Cache: `~/Library/Application Support/LibrusLocal/snapshot.enc`, AES-GCM, prawa 0600.
  Zapis nie zawiera hasła ani cookies.
- Otwarcie wiadomości pobiera pełną treść i oznacza ją jako przeczytaną, jak
  w Librusie. Synchronizacja listy nie zmienia statusu przeczytania.
- Załącznik jest pobierany na kliknięcie, do wskazanego pliku, do 25 MiB.
  Pliki nie są automatycznie otwierane.
- Powiadomienia zawierają liczbę nowych wpisów lub informację o zmianie planu,
  bez ocen i treści wiadomości na ekranie blokady.
- **Wyloguj i usuń lokalne dane** usuwa konto, sesję, klucz cache i cache.
  Usuwa również zadania organizera i odwołuje ich oczekujące przypomnienia.
  Ręcznie pobrane załączniki pozostają w wybranych lokalizacjach.

## Organizer

W zakładce **Organizer** przełączasz listę „Do ogarnięcia” i widok „Najbliższe 7 dni”
(dzisiaj i sześć kolejnych dni). Zadania domowe pojawiają się automatycznie, również
podczas pierwszego pobrania. Starsze niewykonane zadania trafiają do „Zaległe”.
Wpisy bez podanego terminu oddania trafiają do „Bez terminu”; data dodania zadania
nie zastępuje terminu. Po aktualizacji odśwież dane, aby uzupełnić terminy w starszym cache.
Wykonanie zaznaczasz kółkiem przy zadaniu; „Pokaż zrobione” pozwala je przywrócić.
Odhaczenie jest lokalne i nie zmienia niczego w Librusie.

„Nowe zadanie” tworzy własny wpis z opcjonalnym terminem, notatką i przypomnieniem.
Przy otwartej wiadomości, wydarzeniu i zadaniu domowym dostępny jest przycisk
„Dodaj do ogarnięcia”. Kolejne użycie otwiera już powiązane zadanie.
„Zaplanuj przygotowanie” przy wydarzeniu otwiera edytor, w którym możesz wybrać
wcześniejszy termin. W edytorze zadania z organizera „Pokaż źródło” wraca do wpisu;
gdy nie ma go w bieżących danych, pokazuje zapisaną kopię bez pobierania wiadomości.

Synchronizacja zachowuje odhaczenia i notatki. Tytuł i termin automatycznego zadania
aktualizują się z Librusa; własne zadania możesz edytować i usuwać. Zniknięcie
szkolnego wpisu nie usuwa zadania z organizera. Cały organizer jest częścią
szyfrowanych danych offline i pozostaje dostępny po restarcie.

Przypomnienie ma konkretną datę i godzinę; zmiana terminu zadania w Librusie nie
przesuwa go automatycznie. Wymaga włączenia powiadomień Schoolside i zgody macOS.
Zapisane przypomnienia obsługuje system także po zamknięciu aplikacji. Baner nie
zawiera tytułu zadania ani danych ucznia. Wykonanie/usunięcie zadania, wyłączenie
powiadomień lub wylogowanie odwołuje odpowiednie oczekujące przypomnienia.

## Ograniczenia pierwszej wersji

Nieoficjalne API może się zmienić. CAPTCHA lub wymagania dotyczące konta mogą
wymagać działania na oficjalnej stronie. Brak wysyłania wiadomości i usprawiedliwień.
Lista wiadomości obejmuje 50 najnowszych wpisów. Ogłoszenia są wyświetlane bez
ustawiania statusu przeczytania.

Bundle korzysta z `.venv` i źródeł w katalogu projektu. Nie przenoś samej aplikacji
na innego Maca; samodzielny instalator nie jest jeszcze przygotowany. Kompilacja
jest podpisana lokalnie ad hoc, bez publikacji w App Store.

## Testy i kontrola jakości

```bash
.venv/bin/python -m pytest -q
.venv/bin/ruff check src tests scripts
.venv/bin/ruff format --check src tests scripts
.venv/bin/mypy src
.venv/bin/python scripts/verify_native.py
```

Testy używają danych syntetycznych, bez logowania do konta użytkownika. Obejmują
procenty, częściowe awarie, transport sekretów, anulowanie, szyfrowanie i wylogowanie.
Siedemnaście zestawów testów Swift obejmuje też zgodę na powiadomienia i jej cofnięcie,
zapamiętywanie motywu oraz tygodniowy układ planu (w tym weekendy i równoległe lekcje).
Kontrolowany zegar sprawdza odświeżanie po ręcznym pobraniu, zajętą aplikację,
wybudzenie, ponawianie po błędzie sieci oraz zatrzymanie po wylogowaniu i zamknięciu.
Nowe testy sprawdzają trwałość i przeglądanie nowości, zgodność starego cache,
częściowe awarie, zmiany indeksów ID planu, kolejność wydarzeń i czas w Warszawie.
Testy palety sprawdzają kontrast tekstu, akcentu i ostrzeżeń w jasnym/ciemnym
trybie i przy zwiększonym kontraście. Testy przeglądania obejmują filtry ocen,
załączniki na liście wiadomości, zmianę wyboru podczas pobierania oraz spóźnione
odpowiedzi po wylogowaniu. Testy Python obejmują metadane ocen i załączników.
Testy cache używają izolowanego magazynu w pamięci zamiast systemowego Keychain.
Testy organizera obejmują import bez duplikatów, jawne terminy oddania, wykonanie
i notatki podczas synchronizacji, błędy zapisu, restart, ponowne logowanie, zmianę
konta, kopie źródeł oraz odwoływanie przypomnień podczas trwającej aktualizacji.

Osobny test połączenia: `scripts/build_app.py` → `build/Schoolside Connection Check.app`.
Ten test nie zachowuje hasła ani danych konta na dysku.

## Licencja i zależności

Kod Schoolside jest udostępniany na [licencji MIT](LICENSE). Zależności zachowują
własne licencje, opisane w [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md);
pełne teksty i wymagane atrybucje znajdują się w katalogu `third_party/licenses`.
Licencja projektu nie udziela praw do znaków LIBRUS ani dostępu do jego usług.

Integracja używa [nieoficjalnej biblioteki librus-synergia](https://github.com/MichalZaniewicz/librus-synergia),
a nie oficjalnego SDK. Korzystanie z konta podlega
[regulaminowi LIBRUS Synergia](https://synergia.librus.pl/regulamin).

Informacje o bezpiecznym zgłaszaniu problemów: [SECURITY.md](SECURITY.md).
