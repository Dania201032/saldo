package app.budget.budget_app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar

/** Typical texts of Korean banks and card companies (real samples will be added as they come). */
class KrBankParsersTest {
    private val now = Calendar.getInstance().apply { clear(); set(2026, 9, 30, 15, 30) }.timeInMillis
    private val sms = "com.samsung.android.messaging"

    private fun v(pkg: String, title: String, text: String) = BankParsers.classify(pkg, title, text, now)!!
    private fun p(pkg: String, title: String, text: String) = v(pkg, title, text).payment!!

    @Test
    fun amounts() {
        assertEquals(1200000L, KrBankParsers.minorOf("12,000"))
        assertEquals(1250L, KrBankParsers.minorOf("12.50"))
        assertNull(KrBankParsers.minorOf("0"))
    }

    @Test
    fun banksByPackage() {
        assertEquals("tossbank", BankParsers.bankFor("viva.republica.toss", "")!!.key)
        assertEquals("kakaobank", BankParsers.bankFor("com.kakaobank.channel", "")!!.key)
        assertEquals("hana", BankParsers.bankFor("com.kebhana.hanapush", "")!!.key)
        assertEquals("shinhan", BankParsers.bankFor("com.shinhan.sbanking", "")!!.key)
        assertEquals("kb", BankParsers.bankFor("com.kbstar.kbbank", "")!!.key)
        assertEquals("woori", BankParsers.bankFor("com.wooribank.smart.npib", "")!!.key)
        assertEquals("nh", BankParsers.bankFor("nh.smart.nhallonebank", "")!!.key)
        assertEquals("bccard", BankParsers.bankFor("com.bccard.android.mobile", "")!!.key)
        assertNull(BankParsers.bankFor("com.kbsec.mts.android", ""))
    }

    @Test
    fun shinhanCardSms() {
        val r = p(sms, "15447200", "[Web발신]\n신한카드(1234)승인\n홍*동\n12,000원(일시불)\n10/30 12:34\n스타벅스\n누적1,234,567원")
        assertEquals("shinhan", r.app)
        assertEquals("신한카드", r.method)
        assertEquals("sms", r.source)
        assertEquals("expense", r.direction)
        assertEquals(1200000L, r.amountMinor)
        assertEquals("KRW", r.currency)
        assertEquals("스타벅스", r.merchant)
    }

    @Test
    fun kbCardSmsOneLine() {
        val r = p(sms, "15881688", "[KB국민카드]홍*동님 12,000원 일시불 10/30 12:34 GS25 역삼점 누적 1,234,567원")
        assertEquals("kb", r.app)
        assertEquals("expense", r.direction)
        assertEquals(1200000L, r.amountMinor)
        assertEquals("GS25 역삼점", r.merchant)
    }

    @Test
    fun cancelledCardPaymentIsRefund() {
        val r = p(sms, "15447200", "[Web발신]\n신한카드(1234)승인취소\n홍*동\n12,000원(일시불)\n10/30 12:34\n스타벅스")
        assertEquals("income", r.direction)
        assertEquals("스타벅스", r.merchant)
    }

    @Test
    fun foreignCardPayment() {
        val r = p(sms, "15447200", "[Web발신]\n신한카드(1234)해외승인\n홍*동\nUSD 12.50\n10/30 12:34\nAMAZON.COM")
        assertEquals("USD", r.currency)
        assertEquals(1250L, r.amountMinor)
        assertEquals("AMAZON.COM", r.merchant)
    }

    @Test
    fun hanaBankSms() {
        val r = p(sms, "15991111", "[Web발신]\n하나,10/30,12:34\n123-******-45607\n출금12,000원\n스타벅스\n잔액50,000원")
        assertEquals("hana", r.app)
        assertEquals("expense", r.direction)
        assertEquals(1200000L, r.amountMinor)
        assertEquals("스타벅스", r.merchant)
    }

    @Test
    fun shinhanBankSmsWithoutWon() {
        val r = p(sms, "15778000", "[Web발신]\n신한10/30 12:34\n110-***-123456\n입금 50,000\n잔액 1,050,000\n홍길동")
        assertEquals("shinhan", r.app)
        assertEquals("income", r.direction)
        assertEquals(5000000L, r.amountMinor)
        assertEquals("KRW", r.currency)
        assertEquals("홍길동", r.merchant)
    }

    @Test
    fun tossPushes() {
        val i = p("viva.republica.toss", "토스", "홍길동님이 10,000원을 보냈어요")
        assertEquals("tossbank", i.app)
        assertEquals("bank", i.source)
        assertEquals("income", i.direction)
        assertEquals(1000000L, i.amountMinor)
        assertEquals("홍길동", i.merchant)

        val o = p("viva.republica.toss", "토스", "김철수님에게 25,000원을 보냈어요")
        assertEquals("expense", o.direction)
        assertEquals("김철수", o.merchant)

        val c = p("viva.republica.toss", "토스뱅크 체크카드", "스타벅스에서 4,500원 결제했어요")
        assertEquals("expense", c.direction)
        assertEquals(450000L, c.amountMinor)
        assertEquals("스타벅스", c.merchant)
    }

    @Test
    fun kakaoBankPush() {
        val r = p("com.kakaobank.channel", "카카오뱅크", "입금 10,000원 홍길동 | 잔액 50,000원")
        assertEquals("kakaobank", r.app)
        assertEquals("income", r.direction)
        assertEquals(1000000L, r.amountMinor)
        assertEquals("홍길동", r.merchant)

        val o = p("com.kakaobank.channel", "출금", "스타벅스 4,500원 | 잔액 45,500원")
        assertEquals("expense", o.direction)
        assertEquals(450000L, o.amountMinor)
        assertEquals("스타벅스", o.merchant)
    }

    @Test
    fun skipped() {
        assertEquals("promo", v("viva.republica.toss", "토스", "(광고) 토스뱅크 카드 쓰면 최대 10,000원 캐시백!").reason)
        assertEquals("promo", v("com.kakaobank.channel", "카카오뱅크", "26주적금 지금 가입하고 최대 50,000원 받으세요").reason)
        assertEquals("code", v(sms, "15447200", "[Web발신] 인증번호 [123456]를 입력해주세요. 타인에게 알려주지 마세요").reason)
        assertEquals("declined", v(sms, "15447200", "[Web발신] 신한카드(1234) 승인거절 12,000원 잔액부족").reason)
        assertEquals("code", v("com.kakaobank.channel", "카카오뱅크", "새로운 기기에서 로그인했어요").reason)
    }

    @Test
    fun russianSmsStillRussian() {
        val r = p(sms, "900", "Покупка 450р Магнит Баланс: 12 345,67р")
        assertEquals("sber", r.app)
        assertEquals(45000L, r.amountMinor)
    }

    @Test
    fun history() {
        val rows = BankHistory.parse(
            "com.kakaobank.channel",
            listOf("거래내역", "10월 30일 (목)", "스타벅스", "-4,500원", "홍길동", "+10,000원", "10월 29일 (수)", "GS25", "-2,300원"),
            now,
        )
        assertEquals(3, rows.size)
        assertEquals("스타벅스", rows[0].merchant)
        assertEquals("expense", rows[0].direction)
        assertEquals(450000L, rows[0].amountMinor)
        assertEquals("KRW", rows[0].currency)
        assertEquals("income", rows[1].direction)
        assertEquals("GS25", rows[2].merchant)
    }
}
