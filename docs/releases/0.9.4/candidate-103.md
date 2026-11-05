# Кандидат 0.9.4 (103)

- Поводы — проверка 102 владельцем и моя проверка Android на его POCO
  5 ноя.
- `1f7ee47b fix: honest numbers caption`: «Другие увидят …» печатает цифры
  выбранного варианта (`HiddenPartsEditorModel.numbersForOthers`); в 102 при
  «Вся поездка» подпись обещала цифры без скрытого.
- `87ac3ce7 fix: filming history cards`: в режиме съёмки карточка истории
  дочитывает поездку и рисует только видимые куски (`FilmingCardRoute`); в
  102 карта карточки оставалась пустой.
- `a432f508 fix: adaptive profile name`: имя в шапке профиля — одна строка
  с уменьшением до половины, затем две строки по пробелу, без разрыва
  слова. Повод — скриншот владельца, где фамилия разорвалась на третью
  строку одной буквой.
- Исходники: `29c099fa chore: build 103`. Юнит-тесты 3133/0, UI
  `ProfileCardShotTests`, `HiddenPartsSurfaceShotTests`,
  `ForeignTripNavigationTests`, `ProfileLongNameTests`,
  `HiddenPartsEditorShotTests`, `FilmingModeShotTests` зелёные. Проверка
  архива пройдена, та же, что у 101.
- Загружена 5 ноя в 12:43 МСК, символы ушли в Sentry.
- Android в тот же день: 16 (`afb27b5`) прошла проверку Google и активна в
  закрытом треке; правки режима съёмки и имени (`36ab312`, `cbe5a48`) ждут
  сборки 17.
- В 12:48 сборка `VALID`, во внутренней группе `IN_BETA_TESTING`; заметки
  TestFlight (en-US, ru) записаны и сверены обратным чтением.
