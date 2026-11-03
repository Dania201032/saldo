package app.budget.budget_app.capture

/**
 * Korean bank, card and pay notifications (토스뱅크, 카카오뱅크, 하나, 신한, KB국민, 우리, NH농협, IBK, 케이뱅크,
 * card companies, 카카오페이, 네이버페이), as app pushes and as card/bank SMS ("[Web발신] …").
 *
 * Like [BankParsers] this is a generic parser: the operation amount ("12,000원", "₩12,000", "USD 12.50",
 * or a bare number right after 입금/출금 as Shinhan's SMS write it; amounts after 잔액/누적 are the balance),
 * the direction from the operation words, and the payee from "…에서", "…님이/님에게" or the text after the
 * amount. Texts it is built for:
 *   card SMS:  "[Web발신] 신한카드(1234)승인 홍*동 12,000원(일시불) 10/30 12:34 스타벅스 누적1,234,567원"
 *   card SMS:  "[KB국민카드]홍*동님 12,000원 일시불 10/30 12:34 스타벅스 누적 1,234,567원"
 *   bank SMS:  "[Web발신] 하나,10/30,12:34 123-******-45607 출금12,000원 스타벅스 잔액50,000원"
 *   bank SMS:  "[Web발신] 신한10/30 12:34 110-***-123456 입금 50,000 잔액 1,050,000 홍길동"
 *   토스:      "홍길동님이 10,000원을 보냈어요"    "스타벅스에서 4,500원 결제했어요"
 *   카카오뱅크: "입금 10,000원 홍길동 | 잔액 50,000원"
 * Korean ads must start with "(광고)", and banks push codes and limits with amounts, so a notification
 * only counts when it names the operation, or carries a card, an account, a balance or a sign.
 * NOTE: not yet verified against real notifications of these banks; the Bank notifications log in the
 * app shows what was read and why something was skipped.
 */
object KrBankParsers {
    private val BY_PACKAGE = mapOf(
        "viva.republica.toss" to BankParsers.Bank("tossbank", "토스뱅크"),
        "com.kakaobank.channel" to BankParsers.Bank("kakaobank", "카카오뱅크"),
        "com.kakaopay.app" to BankParsers.Bank("kakaopay", "카카오페이"),
        "com.kebhana.hanapush" to BankParsers.Bank("hana", "하나은행"),
        "com.shinhan.sbanking" to BankParsers.Bank("shinhan", "신한은행"),
        "com.shcard.smartpay" to BankParsers.Bank("shinhan", "신한카드"),
        "com.kbstar.kbbank" to BankParsers.Bank("kb", "KB국민은행"),
        "com.kbcard.cxh.appcard" to BankParsers.Bank("kb", "KB국민카드"),
        "com.wooribank.smart.npib" to BankParsers.Bank("woori", "우리은행"),
        "nh.smart.banking" to BankParsers.Bank("nh", "NH농협"),
        "nh.smart.nhallonebank" to BankParsers.Bank("nh", "NH농협"),
        "com.ibk.android.ionebank" to BankParsers.Bank("ibk", "IBK기업은행"),
        "com.kbankwith.smartbank" to BankParsers.Bank("kbank", "케이뱅크"),
        "kr.co.samsungcard.mpocket" to BankParsers.Bank("samsungcard", "삼성카드"),
        "com.hyundaicard.appcard" to BankParsers.Bank("hyundaicard", "현대카드"),
    )

    /** Package-name fragments of other apps of these banks. */
    private val BY_PACKAGE_PART = listOf(
        "republica.toss" to BankParsers.Bank("tossbank", "토스뱅크"), "tossbank" to BankParsers.Bank("tossbank", "토스뱅크"),
        "kakaobank" to BankParsers.Bank("kakaobank", "카카오뱅크"), "kakaopay" to BankParsers.Bank("kakaopay", "카카오페이"),
        "kebhana" to BankParsers.Bank("hana", "하나은행"), "hanabank" to BankParsers.Bank("hana", "하나은행"),
        "hanacard" to BankParsers.Bank("hana", "하나카드"), "hanaskcard" to BankParsers.Bank("hana", "하나카드"), "shinhan" to BankParsers.Bank("shinhan", "신한은행"),
        "shcard" to BankParsers.Bank("shinhan", "신한카드"), "kbstar" to BankParsers.Bank("kb", "KB국민은행"),
        "kbcard" to BankParsers.Bank("kb", "KB국민카드"), "wooribank" to BankParsers.Bank("woori", "우리은행"),
        "wooricard" to BankParsers.Bank("woori", "우리카드"), "nh.smart" to BankParsers.Bank("nh", "NH농협"),
        "nonghyup" to BankParsers.Bank("nh", "NH농협"), "ibk.android" to BankParsers.Bank("ibk", "IBK기업은행"),
        "kbankwith" to BankParsers.Bank("kbank", "케이뱅크"), "samsungcard" to BankParsers.Bank("samsungcard", "삼성카드"),
        "hyundaicard" to BankParsers.Bank("hyundaicard", "현대카드"), "bccard" to BankParsers.Bank("bccard", "BC카드"),
        "naverfin" to BankParsers.Bank("naverpay", "네이버페이"),
    )

    /** Brokerage and certificate apps of the same groups. */
    private val NOT_BANK_PART = Regex("invest|stock|securit|sec\\.|trade|cert|otp|insur", RegexOption.IGNORE_CASE)

    /** A card/bank SMS names the issuer in its text (the sender is a number): the first one named. */
    private val BY_TEXT = listOf(
        Regex("토스뱅크|토스") to BankParsers.Bank("tossbank", "토스뱅크"),
        Regex("카카오뱅크") to BankParsers.Bank("kakaobank", "카카오뱅크"),
        Regex("카카오페이") to BankParsers.Bank("kakaopay", "카카오페이"),
        Regex("하나카드") to BankParsers.Bank("hana", "하나카드"),
        Regex("하나") to BankParsers.Bank("hana", "하나은행"),
        Regex("신한카드") to BankParsers.Bank("shinhan", "신한카드"),
        Regex("신한") to BankParsers.Bank("shinhan", "신한은행"),
        Regex("KB국민카드|국민카드", RegexOption.IGNORE_CASE) to BankParsers.Bank("kb", "KB국민카드"),
        Regex("KB|국민", RegexOption.IGNORE_CASE) to BankParsers.Bank("kb", "KB국민은행"),
        Regex("우리카드") to BankParsers.Bank("woori", "우리카드"),
        Regex("우리") to BankParsers.Bank("woori", "우리은행"),
        Regex("농협|NH", RegexOption.IGNORE_CASE) to BankParsers.Bank("nh", "NH농협"),
        Regex("기업|IBK", RegexOption.IGNORE_CASE) to BankParsers.Bank("ibk", "IBK기업은행"),
        Regex("케이뱅크") to BankParsers.Bank("kbank", "케이뱅크"),
        Regex("네이버페이") to BankParsers.Bank("naverpay", "네이버페이"),
        Regex("삼성카드") to BankParsers.Bank("samsungcard", "삼성카드"),
        Regex("현대카드") to BankParsers.Bank("hyundaicard", "현대카드"),
        Regex("롯데카드") to BankParsers.Bank("lottecard", "롯데카드"),
        Regex("BC카드|비씨카드", RegexOption.IGNORE_CASE) to BankParsers.Bank("bccard", "BC카드"),
    )

    val KEYS: Set<String> = (BY_PACKAGE.values + BY_PACKAGE_PART.map { it.second } + BY_TEXT.map { it.second })
        .map { it.key }.toSet()

    fun bankFor(pkg: String): BankParsers.Bank? {
        BY_PACKAGE[pkg]?.let { return it }
        val lower = pkg.lowercase()
        if (!(lower.startsWith("com.") || lower.startsWith("kr.") || lower.startsWith("viva.") || lower.startsWith("nh."))) return null
        if (NOT_BANK_PART.containsMatchIn(lower)) return null
        return BY_PACKAGE_PART.firstOrNull { lower.contains(it.first) }?.second
    }

    /** Hangul in the text: a Korean notification. */
    private val HANGUL = Regex("[\\uAC00-\\uD7A3]")

    /** A Korean SMS (bank, card, a code or an ad): Russian and Kazakh ones have no Hangul. */
    fun isKoreanSms(text: String): Boolean = HANGUL.containsMatchIn(text)

    /** The issuer named in an SMS; else the plain "SMS" source. */
    fun bankOfSms(text: String): BankParsers.Bank =
        BY_TEXT.mapNotNull { (re, bank) -> re.find(text)?.let { it.range.first to bank } }.minByOrNull { it.first }?.second
            ?: BankParsers.Bank("sms", "SMS")

    private const val NUM = "\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?|\\d+(?:\\.\\d{1,2})?"
    private const val CUR = "원|₩|KRW|USD|US\\$|\\$|달러|EUR|€|유로|JPY|엔|CNY|위안|RUB"

    /** sign, currency before, number, currency after. */
    val AMOUNT_RE = Regex(
        "(?<![\\d.,A-Za-z])([+\\-−–]\\s?)?(?:($CUR)\\s?)?($NUM)(?:\\s?($CUR))?(?![\\d])",
        RegexOption.IGNORE_CASE,
    )

    /** Shinhan and some others write "입금 50,000" without a currency: a number right after the operation. */
    private val BARE_RE = Regex("(입금|출금|지급|결제|승인|이체)\\s?($NUM)(?![\\d.,/:\\-]|\\s?($CUR|월|일|시|분|건))")

    private const val BALANCE_WORDS = "잔액|잔고|누적|사용 ?가능|가능 ?금액|한도|이용 ?가능"
    private val BALANCE_CONTEXT = Regex("($BALANCE_WORDS)[^\\d]{0,8}$")
    private val BALANCE_ANYWHERE = Regex("($BALANCE_WORDS)[^\\d]{0,8}\\d")

    private val CODE_RE = Regex(
        "인증 ?번호|인증 ?코드|승인 ?번호 ?\\[|OTP|비밀 ?번호|로그인|본인 ?확인|보안 ?카드|타인에게 알려주지",
        RegexOption.IGNORE_CASE,
    )
    private val DECLINED_RE = Regex("거절|실패|한도 ?초과|잔액 ?부족|승인 ?불가|불가능|오류|정지된")

    /** Words only ads use; "(광고)" is required by law at the start of an ad. */
    private val AD_RE = Regex("[(\\[]\\s?광고\\s?[)\\]]|이벤트|쿠폰|경품|추첨|당첨|초대|친구에게|무료 ?수신 ?거부")

    /** Looks like an ad: trusted only with a card, an account, a balance or a sign. */
    private val PROMO_RE = Regex(
        "[!?]|\\d\\s?%|최대|혜택|무료|할인|지금|신청|가입|대출|금리|받으세요|해보세요|드려요|드립니다|만나보세요|확인해 ?보세요"
    )

    /** Money coming back: a cancelled payment or a refund. */
    private val REFUND_RE = Regex("취소|환불|반품")

    /** Direction words; the first one in the text decides. */
    private val INCOME_RE = Regex("입금|받았|받은|받기|들어왔|급여|월급|충전|이자 ?지급|님이\\s?\\S*\\s?보냈|님이 [^.]{0,30}보냈")
    private val EXPENSE_RE = Regex(
        "출금|결제|승인|사용(?! ?가능)|보냈|송금|이체|지급|구매|납부|인출|빠져나|님(에게|께|한테)"
    )

    /** A masked card or account ("신한카드(1234)", "*1234", "123-***-456"): proves an operation. */
    private val CARD_MASK_RE = Regex("카드\\s?\\(?\\d{4}\\)?|\\(\\d{4}\\)|\\*\\d{3,4}(?!\\d)|\\d{2,4}-\\*{2,}|\\*{3,}|일시불|할부")

    /** Not a payee: the date and time, the masked holder ("홍*동님"), card/bank headers, operation words. */
    private val DATETIME_RE = Regex("\\d{1,2}[/.-]\\d{1,2}(\\s?\\d{1,2}:\\d{2})?|\\d{1,2}:\\d{2}(:\\d{2})?")
    private val NOISE_RE = Regex(
        "\\[?web ?발신\\]?|\\[[^\\]]{0,20}\\]|\\S*\\*\\S*님?|\\S+님(?=\\s|$)|\\(?일시불\\)?|\\(?할부\\s?\\d*개?월?\\)?|" +
            "\\d{2,4}-[*\\d-]{3,}|체크|신용|해외|국내|승인|취소|결제|출금|입금|이체|사용|지급|완료|되었습니다|했어요|됐어요|" +
            "(?<!\\S)(을|를|원)(?!\\S)",
        RegexOption.IGNORE_CASE,
    )
    private val BANKWORD_RE = Regex(
        "^(토스뱅크|토스|카카오뱅크|카카오페이|하나은행|하나카드|하나|신한은행|신한카드|신한|kb국민은행|kb국민카드|국민은행|국민카드|kb|" +
            "우리은행|우리카드|우리|nh농협|농협|nh|ibk기업은행|ibk|기업|케이뱅크|네이버페이|삼성카드|현대카드|롯데카드|bc카드|비씨카드|" +
            "입출금통장|통장|체크카드|신용카드|카드|계좌|입금|출금|결제|승인|알림|sms)\\S{0,4}$",
        RegexOption.IGNORE_CASE,
    )

    fun currencyOf(s: String): String = when (s.lowercase()) {
        "", "원", "₩", "krw" -> "KRW"
        "usd", "us$", "$", "달러" -> "USD"
        "eur", "€", "유로" -> "EUR"
        "jpy", "엔" -> "JPY"
        "cny", "위안" -> "CNY"
        "rub" -> "RUB"
        else -> "KRW"
    }

    /** "12,000" -> 1200000 (hundredths, as for every currency); "12.50" -> 1250; null for zero. */
    fun minorOf(number: String): Long? =
        number.replace(",", "").toBigDecimalOrNull()?.movePointRight(2)?.toLong()?.takeIf { it > 0 }

    fun classify(bank: BankParsers.Bank, title: String, text: String, now: Long, sms: Boolean): BankParsers.Verdict {
        fun clean(s: String) = s.replace(Regex("[ \\t\\u00A0]+"), " ").trim()
        // An SMS title is only the sender's number.
        val head = if (sms) "" else clean(title).replace('\n', ' ')
        val main = clean(text)
        val lines = (listOf(head) + main.split('\n')).map { it.trim() }.filter { it.isNotEmpty() }
        val body = lines.joinToString(" ")
        if (body.isEmpty()) return BankParsers.Verdict(null, "no_amount")
        when {
            CODE_RE.containsMatchIn(body) -> return BankParsers.Verdict(null, "code")
            DECLINED_RE.containsMatchIn(body) -> return BankParsers.Verdict(null, "declined")
            AD_RE.containsMatchIn(body) -> return BankParsers.Verdict(null, "promo")
        }

        // The operation amount: with a currency, or a bare number right after 입금/출금; not after 잔액/누적.
        val withCurrency = AMOUNT_RE.findAll(body).firstOrNull {
            (it.groupValues[2].isNotEmpty() || it.groupValues[4].isNotEmpty()) &&
                !BALANCE_CONTEXT.containsMatchIn(body.substring(0, it.range.first))
        }
        val bare = BARE_RE.find(body)?.takeIf { b -> withCurrency == null || b.range.first < withCurrency.range.first }
        val number: String
        val currency: String
        val sign: String
        val range: IntRange
        if (bare != null) {
            number = bare.groupValues[2]
            currency = "KRW"
            sign = ""
            range = bare.groups[2]!!.range
        } else if (withCurrency != null) {
            number = withCurrency.groupValues[3]
            currency = currencyOf(withCurrency.groupValues[2].ifEmpty { withCurrency.groupValues[4] })
            sign = withCurrency.groupValues[1].trim()
            range = withCurrency.range
        } else {
            return BankParsers.Verdict(null, "no_amount")
        }
        val amount = minorOf(number) ?: return BankParsers.Verdict(null, "no_amount")

        val refund = REFUND_RE.containsMatchIn(body)
        val inc = INCOME_RE.find(body)
        val exp = EXPENSE_RE.find(body)
        val operation = refund || inc != null || exp != null
        val hard = sign.isNotEmpty() || CARD_MASK_RE.containsMatchIn(body) || BALANCE_ANYWHERE.containsMatchIn(body)
        val promo = PROMO_RE.containsMatchIn(body)
        if (!hard && (promo || !operation)) return BankParsers.Verdict(null, if (promo) "promo" else "not_operation")

        val direction = when {
            sign == "+" -> "income"
            sign.isNotEmpty() -> "expense"
            refund -> "income"
            inc != null && (exp == null || inc.range.first <= exp.range.first) -> "income"
            exp != null -> "expense"
            else -> "expense"
        }
        val payment = CapturedPayment(
            source = if (sms) "sms" else "bank",
            app = bank.key,
            direction = direction,
            amountMinor = amount,
            currency = currency,
            merchant = merchantOf(head, lines, body, range),
            method = bank.name,
            ts = now,
            raw = "$title | $text".take(500),
        )
        return BankParsers.Verdict(payment, "recorded")
    }

    private val PERSON_RE = Regex("([\\p{L}][^\\s*]{0,15})님(이|에게|께|한테|으로부터)")
    private val NOT_PERSON = Regex("^(고객|회원|사장|대표)$")
    private val AT_RE = Regex("([^\\s|.,][^|\\n]{0,30}?)에서(?=\\s|\\d|$)")
    private val STOP_RE = Regex("\\s?($BALANCE_WORDS)|\\s?\\|")

    private fun merchantOf(head: String, lines: List<String>, body: String, amount: IntRange): String? {
        // "홍길동님이 10,000원을 보냈어요", "홍길동님에게 …"
        PERSON_RE.findAll(body).map { it.groupValues[1].trim() }.firstOrNull { !NOT_PERSON.matches(it) }?.let { return it }
        // "스타벅스에서 4,500원 결제했어요" (line by line: the title is the bank or the card)
        for (line in lines) AT_RE.find(line)?.let { m -> pick(m.groupValues[1])?.let { return it } }
        // The text after the amount, piece by piece: "(일시불) 10/30 12:34 스타벅스 누적…".
        val after = body.substring(amount.last + 1)
        val stop = STOP_RE.find(after)?.range?.first ?: after.length
        for (piece in after.substring(0, stop).split(DATETIME_RE)) pick(piece)?.let { return it }
        // Bank SMS put the other side last, after the balance: "입금 50,000 잔액 1,050,000 홍길동".
        AMOUNT_RE.findAll(after).lastOrNull()?.let { last ->
            pick(after.substring(last.range.last + 1).substringBefore('|'))?.let { return it }
        }
        // Before the amount, nearest first ("스타벅스 | 4,500원").
        val before = body.substring(0, amount.first)
        for (piece in before.split(DATETIME_RE, 0).reversed()) {
            val p = pick(piece.substringAfterLast('|'))
            if (p != null) return p
        }
        return null
    }

    /** A piece of text as a payee, or null when it is only noise, a number or the bank's own name. */
    private fun pick(s: String): String? {
        var t = s.replace(AMOUNT_RE, " ").replace(NOISE_RE, " ").replace(Regex("\\s+"), " ")
            .trim(' ', '.', ',', ';', ':', '-', '—', '|', '(', ')', '"', '\'')
        if (t.length > 40) t = t.take(40).trim()
        if (t.length < 2 || t.all { it.isDigit() || it.isWhitespace() }) return null
        if (BANKWORD_RE.matches(t)) return null
        return t
    }
}
