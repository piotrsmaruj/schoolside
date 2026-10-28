# Licencje zależności Schoolside

Kod projektu podlega licencji MIT z pliku `LICENSE`. Zależności są instalowane
osobno przez `uv sync --locked` i zachowują własne licencje. Nie są objęte licencją
MIT Schoolside. Nie dołączamy ich kodu ani środowiska `.venv` do repozytorium.

Zestawienie odpowiada wersjom z `uv.lock` zainstalowanym na macOS / Python 3.13.
Obejmuje zależności wykonawcze, narzędzia deweloperskie i ich zależności pośrednie.
Pełne teksty licencji, NOTICE i atrybucje skopiowano bez zmian z metadanych
zainstalowanych dystrybucji do `third_party/licenses/<pakiet>/`.

Apple SDK i frameworki systemowe nie są dołączane do repozytorium. Budowanie
wymaga narzędzi Apple udostępnianych na ich własnych warunkach. Po zmianie
`uv.lock` należy zaktualizować to zestawienie i dołączone teksty.

## Zależności wykonawcze

| Pakiet | Wersja | Licencja | Pliki |
| --- | --- | --- | --- |
| [aiohappyeyeballs](https://pypi.org/project/aiohappyeyeballs/2.7.1/) | 2.7.1 | PSF-2.0 | [Teksty](third_party/licenses/aiohappyeyeballs) |
| [aiohttp](https://pypi.org/project/aiohttp/3.14.5/) | 3.14.5 | Apache-2.0 AND MIT | [Teksty](third_party/licenses/aiohttp) |
| [aiosignal](https://pypi.org/project/aiosignal/1.4.0/) | 1.4.0 | Apache-2.0 | [Teksty](third_party/licenses/aiosignal) |
| [attrs](https://pypi.org/project/attrs/26.1.0/) | 26.1.0 | MIT | [Teksty](third_party/licenses/attrs) |
| [frozenlist](https://pypi.org/project/frozenlist/1.8.0/) | 1.8.0 | Apache-2.0 | [Teksty](third_party/licenses/frozenlist) |
| [idna](https://pypi.org/project/idna/3.20/) | 3.20 | BSD-3-Clause | [Teksty](third_party/licenses/idna) |
| [librus-synergia](https://pypi.org/project/librus-synergia/0.3.29/) | 0.3.29 | MIT | [Teksty](third_party/licenses/librus-synergia) |
| [multidict](https://pypi.org/project/multidict/7.2.1/) | 7.2.1 | Apache-2.0 | [Teksty](third_party/licenses/multidict) |
| [propcache](https://pypi.org/project/propcache/0.5.4/) | 0.5.4 | Apache-2.0 | [Teksty](third_party/licenses/propcache) |
| [tzdata](https://pypi.org/project/tzdata/2026.5/) | 2026.5 | Apache-2.0 | [Teksty](third_party/licenses/tzdata) |
| [yarl](https://pypi.org/project/yarl/1.25.1/) | 1.25.1 | Apache-2.0 | [Teksty](third_party/licenses/yarl) |

## Narzędzia deweloperskie i ich zależności

| Pakiet | Wersja | Licencja | Pliki |
| --- | --- | --- | --- |
| [iniconfig](https://pypi.org/project/iniconfig/2.3.1/) | 2.3.1 | MIT | [Teksty](third_party/licenses/iniconfig) |
| [librt](https://pypi.org/project/librt/0.16.0/) | 0.16.0 | MIT | [Teksty](third_party/licenses/librt) |
| [mypy](https://pypi.org/project/mypy/1.20.2/) | 1.20.2 | MIT | [Teksty](third_party/licenses/mypy) |
| [mypy_extensions](https://pypi.org/project/mypy_extensions/1.1.0/) | 1.1.0 | MIT | [Teksty](third_party/licenses/mypy_extensions) |
| [packaging](https://pypi.org/project/packaging/26.3/) | 26.3 | Apache-2.0 OR BSD-2-Clause | [Teksty](third_party/licenses/packaging) |
| [pathspec](https://pypi.org/project/pathspec/1.1.1/) | 1.1.1 | MPL-2.0 | [Teksty](third_party/licenses/pathspec) |
| [pluggy](https://pypi.org/project/pluggy/1.7.0/) | 1.7.0 | MIT | [Teksty](third_party/licenses/pluggy) |
| [Pygments](https://pypi.org/project/Pygments/2.21.0/) | 2.21.0 | BSD-2-Clause | [Teksty](third_party/licenses/pygments) |
| [pytest](https://pypi.org/project/pytest/9.2.0/) | 9.2.0 | MIT | [Teksty](third_party/licenses/pytest) |
| [ruff](https://pypi.org/project/ruff/0.17.3/) | 0.17.3 | MIT | [Teksty](third_party/licenses/ruff) |
| [typing_extensions](https://pypi.org/project/typing_extensions/4.16.0/) | 4.16.0 | PSF-2.0 | [Teksty](third_party/licenses/typing_extensions) |

## Dodatkowe atrybucje

- `librus-synergia`: Copyright (c) 2026 Michał Zaniewicz; MIT. Biblioteka jest
  nieoficjalna i nie stanowi potwierdzenia współpracy projektu z LIBRUS.
- `aiohttp`: Apache-2.0 oraz MIT dla dołączonego `llhttp`; oba teksty są zachowane.
- `yarl` i `propcache`: zachowano także pliki `NOTICE`.
- `mypy`: zachowano także licencję dołączonego `typeshed`.
- `tzdata`: zachowano atrybucje i pełny tekst Apache-2.0.
- `pathspec` to narzędzie deweloperskie na MPL-2.0, pobierane osobno; nie dołączamy
  jego kodu ani binariów do aplikacji.

Nazwy i znaki LIBRUS / LIBRUS Synergia należą do ich uprawnionych właścicieli.
Są używane opisowo w celu wskazania zgodności. Licencje kodu nie przyznają praw
do tych znaków ani do materiałów lub danych dostępnych w usłudze.
