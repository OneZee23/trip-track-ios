import Foundation
import OSLog
import Sentry

/// Thin wrapper around `SentrySDK.start` that bakes in TripTrack's
/// privacy stance:
///   - DSN sourced from Info.plist via `AppConfig.sentryDSN`. Empty DSN
///     → no-op start (dev / simulator builds skip Sentry entirely).
///   - No screenshot, no view-hierarchy, no session replay. Privacy
///     surfaces stay strictly off — driving routes & photos must NEVER
///     leak via diagnostic snapshots.
///   - PII scrubber on `beforeSend`, `beforeBreadcrumb` и `beforeSendSpan`
///     mirrors the existing `APILogger.redact` whitelist (auth tokens,
///     email, names, remote URLs) через общий `PIIScrubber`.
///   - Auto-instrumentation kept lean: crashes + unhandled exceptions
///     ON, network performance OFF (URL paths can carry trip ids).
///
/// **ПОЧЕМУ так подробно про автоматику SDK.** Опасное здесь — не то, что
/// мы отправляем руками (ручных `capture` в приложении НЕТ ни одного), а
/// то, что SDK включает сам, по умолчанию, без единой строки у нас:
/// `enableCaptureFailedRequests`, `enableNetworkTracking`,
/// `enableFileIOTracing` — все три в 8.58 приходят включёнными. Каждая
/// уносит URL или путь к файлу. Поэтому ниже выключено и отфильтровано
/// ЯВНО: значение по умолчанию — не решение, а то, что кто-то другой
/// решил за нас и может поменять в следующей минорной версии.
enum SentryService {
    private static let log = Logger(subsystem: "com.triptrack", category: "sentry")

    static func start() {
        guard let dsn = AppConfig.sentryDSN else {
            // ПОЧЕМУ вслух, а не молча: пустой DSN — не «дев-режим», а
            // состояние, в котором приложение уехало в App Store ДЕСЯТЬ
            // релизов подряд. В архивах 0.5.5, 0.5.8, 0.6.1, 0.6.4 и 0.6.5
            // `SENTRY_DSN` пуст — то есть краш-репортов не было ни у одной
            // выпущенной версии, и именно тихий `return` сделал это
            // незаметным. Строка в системном логе ничего не меняет в
            // поведении сборки, но следующему человеку отвечает на вопрос
            // «почему в Sentry пусто» за секунду, а не за вечер.
            log.notice("Sentry выключен: SENTRY_DSN пуст")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Self.releaseString
            options.environment = AppConfig.isDebug ? "debug" : "release"

            // Bound transaction sampling — for an early-stage app the
            // free tier is plenty at 10%, and we don't have user-load
            // worth profiling beyond that. Профайлер выключен совсем:
            // он стоит батареи на реальном телефоне, который и так пишет
            // GPS в фоне.
            options.tracesSampleRate = 0.1
            options.profilesSampleRate = 0.0

            // Hard "no" to surfaces that could leak driving data.
            // Session replay is OFF by default (opt-in via experimental
            // options); we deliberately do not configure it so capture
            // never starts. Same for screenshots / view hierarchies.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // We attach our own user scope (only the anonymous account
            // id, no name / email). Disable Sentry's default user info
            // collection so device identifiers don't leak. По умолчанию в
            // SDK это тоже `false` — пишем явно, потому что от значения
            // зависит ещё и автоподстановка IP-адреса на сервере
            // (`SentrySDKSettings.autoInferIP`).
            options.sendDefaultPii = false

            // Network breadcrumbs: keep them, but `beforeBreadcrumb`
            // strips URL paths so per-trip / per-photo identifiers
            // don't end up in event payloads.
            options.enableAutoBreadcrumbTracking = true

            // ПОЧЕМУ выключено: спаны сетевых запросов кладут в `data`
            // полный URL, `http.query` и `http.fragment`
            // (`SentryNetworkTracker`), а описание спана — это «GET /путь».
            // Доккоммент этого файла обещал «network performance OFF» с
            // самого начала, но строки не было — и SDK держал своё
            // умолчание (включено). Форму запроса нам отдают крошки, они
            // проходят через `beforeBreadcrumb`.
            options.enableNetworkTracking = false

            // ПОЧЕМУ выключено: спан файловой операции описывается ПУТЁМ к
            // файлу, а у нас это `…/Documents/…/<id фотографии>.jpg` —
            // идентификаторы личных снимков. Диагностической ценности при
            // 10% трейсов ноль, цена — утечка.
            options.enableFileIOTracing = false

            // CoreData-трейсинг оставлен: `SentryPredicateDescriptor`
            // подставляет вместо КОНСТАНТ предиката `%@`, то есть в спан
            // уезжает форма запроса («startDate >= %@»), а не даты, id и
            // координаты. Проверено по исходникам 8.58.2.
            options.enableCoreDataTracing = true

            // Ошибочные HTTP-ответы оставлены включёнными — это половина
            // пользы Sentry для нас (прод-каскад USER_NOT_AUTH был виден
            // только в серверных логах). Но событие несёт `request.url`,
            // `request.queryString` и `request.fragment` целиком —
            // вычищаются в `scrub(event:)` ниже. Тела запроса и ответа SDK
            // не прикладывает (только `bodySize`), поэтому заметки, имена
            // отметок и координаты поездок в событие не попадают.
            options.enableCaptureFailedRequests = true

            options.beforeSend = { event in
                Self.scrub(event: event)
                return event
            }

            options.beforeBreadcrumb = { breadcrumb in
                Self.scrub(breadcrumb: breadcrumb)
                return breadcrumb
            }

            // Страховка на случай, если сетевой трейсинг когда-нибудь
            // включат обратно: спан тоже чистится.
            options.beforeSendSpan = { span in
                Self.scrub(span: span)
                return span
            }
        }
    }

    /// Stamp the current authenticated account id (UUID, no PII) onto
    /// the Sentry scope so events get grouped per-user without revealing
    /// who that user actually is. Call after sign-in / on cold-launch
    /// when a session restores. Pass `nil` on sign-out to clear.
    static func setAccount(id: String?) {
        SentrySDK.configureScope { scope in
            if let id {
                let user = User()
                user.userId = id
                scope.setUser(user)
            } else {
                scope.setUser(nil)
            }
        }
    }

    // MARK: - Scrubbing

    private static func scrub(event: Event) {
        // Tags & extras: drop sensitive entries entirely.
        if let tags = event.tags {
            event.tags = tags.filter { !PIISensitiveKeys.all.contains($0.key) }
        }
        if let extra = event.extra {
            event.extra = PIIScrubber.redact(dict: extra)
        }
        // `context` наполняет сам SDK, и туда же складывается ответ
        // сервера у событий HTTPClientError. Ходим тем же ситом.
        if let context = event.context {
            event.context = context.mapValues { PIIScrubber.redact(dict: $0) }
        }
        // Request cookies / auth headers — defense in depth. The SDK
        // doesn't capture HTTP bodies by default; we still strip auth
        // headers in case automatic instrumentation gets enabled later.
        if let request = event.request {
            request.cookies = nil
            request.headers = (request.headers ?? [:]).filter {
                !$0.key.lowercased().contains("authorization") &&
                !$0.key.lowercased().contains("cookie")
            }
            // ПОЧЕМУ обязательно: `enableCaptureFailedRequests` (включён
            // по умолчанию в SDK) на каждый 5xx строит событие с
            // `url` = путь целиком и `queryString` = query целиком. То
            // есть `/users/<accountId>/trips?cursor=<дата>|<id поездки>`
            // уезжает в Sentry без единой нашей строки кода. Оставляем
            // форму пути — «какой эндпоинт упал» видно, «кто и куда
            // ездил» нет.
            if let url = request.url {
                request.url = PIIScrubber.redactURL(url)
            }
            request.queryString = nil
            request.fragment = nil
        }
    }

    private static func scrub(breadcrumb: Breadcrumb) {
        // Оригинальный URL берём ДО общей чистки: `url` есть в списке
        // чувствительных имён (там же живут presigned-ссылки на фото), и
        // общий проход заменит его целиком.
        let originalURL = breadcrumb.data?["url"] as? String

        if let data = breadcrumb.data {
            breadcrumb.data = PIIScrubber.redact(dict: data)
        }

        guard breadcrumb.category == "http" || breadcrumb.type == "http" else { return }

        var data = breadcrumb.data ?? [:]
        // Крошки сетевого слоя (`SentryNetworkTracker`) кладут сюда три
        // ключа: `url`, `http.query`, `http.fragment`. Первый возвращаем в
        // безопасной форме (схема + хост + форма пути) — без него крошка
        // бесполезна; два других выкидываем: в query у нас курсор ленты
        // (`дата|id поездки`) и `vehicleId`.
        if let originalURL {
            data["url"] = PIIScrubber.redactURL(originalURL)
        }
        data.removeValue(forKey: "http.query")
        data.removeValue(forKey: "http.fragment")
        breadcrumb.data = data
    }

    private static func scrub(span: Span) {
        for key in ["http.query", "http.fragment"] where span.data[key] != nil {
            span.removeData(key: key)
        }
        if let url = span.data["url"] as? String {
            span.setData(value: PIIScrubber.redactURL(url), key: "url")
        }
        // Описание сетевого спана — «GET https://host/путь/<id>»; у
        // файлового — путь к файлу. Прогоняем через ту же чистку, если в
        // нём вообще есть URL.
        if let desc = span.spanDescription, desc.contains("://") {
            let parts = desc.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                span.spanDescription = "\(parts[0]) \(PIIScrubber.redactURL(parts[1]))"
            } else {
                span.spanDescription = PIIScrubber.redactURL(desc)
            }
        }
    }

    // MARK: - Release string

    /// `MARKETING_VERSION (CURRENT_PROJECT_VERSION)` — Sentry uses this to
    /// group events per build, makes regressions easy to bisect.
    private static var releaseString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "triptrack-ios@\(marketing)+\(build)"
    }
}
