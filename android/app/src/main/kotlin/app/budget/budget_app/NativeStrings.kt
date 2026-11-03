package app.budget.budget_app

import android.content.Context

/** Texts shown by the native side (notifications), in the app language chosen in Flutter. Order: ru, en, zh, kk, de, nl, ko. */
object NativeStrings {
    private const val PREFS = "budget_prefs"
    private const val KEY_LANG = "lang"
    private val LANGS = listOf("ru", "en", "zh", "kk", "de", "nl", "ko")

    private val S = mapOf(
        "recorded" to listOf("Записано: {0}", "Recorded: {0}", "已记录：{0}", "Жазылды: {0}", "Erfasst: {0}", "Vastgelegd: {0}", "기록됨: {0}"),
        "tap_to_check" to listOf("нажмите, чтобы проверить", "tap to check", "点击查看", "тексеру үшін басыңыз", "zum Prüfen tippen", "tik om te controleren", "눌러서 확인"),
        "transfer_from" to listOf(
            "Перевод от {0} в WeChat", "Transfer from {0} in WeChat", "{0} 的微信转账", "{0} жіберген WeChat аударымы",
            "Überweisung von {0} in WeChat", "Overboeking van {0} in WeChat", "{0}님의 WeChat 이체",
        ),
        "transfer_accepted" to listOf(
            "Ваш перевод {0} в WeChat принят", "{0} accepted your WeChat transfer", "{0} 已收下你的微信转账", "{0} WeChat аударымыңызды қабылдады",
            "{0} hat Ihre WeChat-Überweisung angenommen", "{0} heeft uw WeChat-overboeking geaccepteerd", "{0}님이 WeChat 이체를 받았어요",
        ),
        "how_much" to listOf(
            "Сколько? WeChat не показывает сумму в уведомлении", "How much? WeChat doesn't show the amount",
            "多少钱？微信通知中不显示金额", "Қанша? WeChat хабарламада соманы көрсетпейді",
            "Wie viel? WeChat zeigt den Betrag nicht an", "Hoeveel? WeChat toont het bedrag niet", "얼마인가요? WeChat은 알림에 금액을 보여 주지 않아요",
        ),
        "enter_amount" to listOf("Ввести сумму", "Enter amount", "输入金额", "Соманы енгізу", "Betrag eingeben", "Bedrag invoeren", "금액 입력"),
        "dont_record" to listOf("Не записывать", "Don't record", "不记录", "Жазбау", "Nicht erfassen", "Niet vastleggen", "기록하지 않기"),
        "amount_label" to listOf("Сумма", "Amount", "金额", "Сома", "Betrag", "Bedrag", "금액"),
        "not_understood" to listOf(
            "Не понял сумму «{0}»", "Couldn't read “{0}”", "无法识别“{0}”", "«{0}» сомасы түсініксіз",
            "„{0}“ nicht verstanden", "‘{0}’ niet begrepen", "“{0}” 금액을 알 수 없어요",
        ),
        "waiting_review" to listOf(
            "Перевод ждёт в «Разборе автозаписей»", "The transfer is waiting in Review", "转账在“确认自动记录”中等待",
            "Аударым «Қарау» бөлімінде күтіп тұр", "Die Überweisung wartet in „Prüfen“", "De overboeking wacht bij ‘Controleren’", "이체가 “확인”에서 기다리고 있어요",
        ),
        "split_more" to listOf("Разделить…", "Split…", "分账…", "Бөлу…", "Teilen…", "Delen…", "나누기…"),
        "for_friend" to listOf("За друга", "For a friend", "替朋友付", "Дос үшін", "Für einen Freund", "Voor een vriend", "친구 대신"),
        "reminders_channel" to listOf("Регулярные платежи", "Regular payments", "定期付款", "Тұрақты төлемдер", "Regelmäßige Zahlungen", "Vaste betalingen", "정기 결제"),
        "payee_ask" to listOf("Где?", "Where?", "在哪？", "Қайда?", "Wo?", "Waar?", "어디서?"),
        "payee_label" to listOf(
            "Где или за что платили", "Where or what for", "在哪里或买了什么", "Қайда немесе не үшін", "Wo oder wofür", "Waar of waarvoor", "어디서 또는 무엇에 썼나요",
        ),
        "for_friend_done" to listOf(
            "За друга: вам должны {0}", "For a friend: you are owed {0}", "替朋友付：朋友欠你 {0}", "Дос үшін: сізге {0} қарыз",
            "Für einen Freund: man schuldet Ihnen {0}", "Voor een vriend: men is u {0} verschuldigd", "친구 대신: 받을 돈 {0}",
        ),
        "split_done" to listOf(
            "Разделено на {0}: ваша доля {1}", "Split by {0}: your share {1}", "已平分为 {0} 份：你的份额 {1}", "{0}-ге бөлінді: сіздің үлесіңіз {1}",
            "Durch {0} geteilt: Ihr Anteil {1}", "Gedeeld door {0}: uw deel {1}", "{0}명으로 나눴어요: 내 몫 {1}",
        ),
        "channel" to listOf(
            "Записанные платежи", "Recorded payments", "已记录的付款", "Жазылған төлемдер", "Erfasste Zahlungen", "Vastgelegde betalingen", "기록된 결제",
        ),
    )

    fun lang(ctx: Context): String = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LANG, "ru") ?: "ru"

    fun setLang(ctx: Context, lang: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_LANG, lang).apply()
    }

    fun t(ctx: Context, key: String, vararg args: Any): String {
        val list = S[key] ?: return key
        var s = list[LANGS.indexOf(lang(ctx)).coerceAtLeast(0)]
        args.forEachIndexed { i, a -> s = s.replace("{$i}", a.toString()) }
        return s
    }
}
