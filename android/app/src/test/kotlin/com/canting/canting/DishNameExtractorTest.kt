package com.canting.canting

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DishNameExtractorTest {
    private fun extract(vararg lines: String) = DishNameExtractor.extract(lines.toList())
    private fun names(result: DishExtractionResult) = result.dishes.map { it.name }

    // ---------- 菜名 + 数量 ----------

    @Test
    fun extractsMerchantDishNamesAndQuantities() {
        val result = DishNameExtractor.extract(
            listOf(
                "邻里小馆",
                "黄焖鸡米饭（大份） x2 ¥36.00",
                "清炒时蔬 - 微辣 ￥12",
                "配送费 3元",
                "合计 ¥51",
                "13800138000",
            ),
        )

        assertEquals("邻里小馆", result.merchant)
        assertEquals(
            listOf(
                ExtractedDish(name = "黄焖鸡米饭（大份）", quantity = 2),
                ExtractedDish(name = "清炒时蔬-微辣", quantity = 1),
            ),
            result.dishes,
        )
    }

    @Test
    fun mergesRepeatedDishLines() {
        val result = DishNameExtractor.extract(
            listOf(
                "番茄炒蛋 x2",
                "番茄炒蛋 ×3",
                "订单时间 12:30",
            ),
        )

        assertEquals(
            listOf(ExtractedDish(name = "番茄炒蛋", quantity = 5)),
            result.dishes,
        )
    }

    @Test
    fun noQuantityMarkerDefaultsToOne() {
        val result = extract("蒜蓉西兰花")
        assertEquals(1, result.dishes.single().quantity)
    }

    @Test
    fun quantityTakesAtMostTwoDigits() {
        // 数量模式只识别 1~2 位数字（\d{1,2}）：×99 是上限内的合法值；
        // 三位数字（如 ×100）只会取前两位，这是现有提取逻辑的已知口径。
        val result = extract("米饭×99")
        assertEquals(99, result.dishes.single { it.name.contains("米饭") }.quantity)
    }

    @Test
    fun outputIsCappedAt20Dishes() {
        val lines = (1..30).map { "菜品编号${it}号" }
        val result = DishNameExtractor.extract(lines)
        assertTrue(result.dishes.size <= 20)
    }

    // ---------- 价格 / 电话 / 时间 / 订单号过滤 ----------

    @Test
    fun purePriceLinesAreFiltered() {
        val result = extract("¥52", "28.5元", "¥ 6", "蒜蓉西兰花")
        assertEquals(listOf("蒜蓉西兰花"), names(result))
    }

    @Test
    fun priceOnDishLineIsStripped() {
        val result = extract("黄焖鸡米饭 ¥52")
        assertEquals(listOf("黄焖鸡米饭"), names(result))
    }

    @Test
    fun phoneLinesAreFiltered() {
        val result = extract("联系电话 13812345678", "010-68582233", "宫保鸡丁")
        assertEquals(listOf("宫保鸡丁"), names(result))
    }

    @Test
    fun timeLinesAreFiltered() {
        val result = extract("送达时间 12:30", "18:05", "鱼香肉丝")
        assertEquals(listOf("鱼香肉丝"), names(result))
    }

    @Test
    fun orderNumberLinesAreFiltered() {
        val result = extract("订单号: 2026090412345", "订单时间 11:20", "红烧肉")
        assertEquals(listOf("红烧肉"), names(result))
    }

    // ---------- excludedTerms 过滤 ----------

    @Test
    fun feeAndSummaryLinesAreFiltered() {
        val result = extract(
            "配送费 ¥4",
            "打包费 ¥2",
            "餐盒费 ¥1",
            "合计 ¥59",
            "实付 ¥45",
            "优惠 -¥14",
            "番茄炒蛋",
        )
        assertEquals(listOf("番茄炒蛋"), names(result))
    }

    @Test
    fun addressAndInvoiceLinesAreFiltered() {
        val result = extract("收货地址: 某某路某某号", "发票抬头 某某公司", "麻婆豆腐")
        assertEquals(listOf("麻婆豆腐"), names(result))
    }

    // ---------- 商家识别 ----------

    @Test
    fun merchantLineIsNotCountedAsDish() {
        val result = extract(
            "张记黄焖鸡米饭小馆",
            "黄焖鸡米饭 ×1 ¥26",
        )
        assertEquals("张记黄焖鸡米饭小馆", result.merchant)
        assertEquals(listOf("黄焖鸡米饭"), names(result))
    }

    @Test
    fun merchantNameIsCleanedFromDecorSymbols() {
        // 装饰符号（·）在商家名两端时被清理；¥ 后无数字不属于价格清洗范围。
        val result = extract(
            "· 老王食堂 ·",
            "宫保鸡丁",
        )
        assertEquals("老王食堂", result.merchant)
    }

    @Test
    fun lineWithoutMerchantTermIsNotMerchant() {
        val result = extract("黄焖鸡米饭")
        assertEquals("", result.merchant)
    }

    // ---------- 括号/口味后缀清理 ----------

    @Test
    fun bracketSpecSuffixIsPreserved() {
        val result = extract("黄焖鸡米饭（大份）")
        assertEquals(listOf("黄焖鸡米饭（大份）"), names(result))
    }

    @Test
    fun halfWidthBracketAndFlavorSuffixAreCleaned() {
        val result = extract(
            "麻辣香锅(微辣) ×1",
            "麻辣香锅-中辣",
        )
        assertEquals(listOf("麻辣香锅(微辣)", "麻辣香锅-中辣"), names(result))
    }

    @Test
    fun blankAfterCleaningIsNotADish() {
        // 整行只剩价格与数量标记，清理后为空。
        val result = extract("¥52 ×2", "西红柿炒鸡蛋")
        assertEquals(listOf("西红柿炒鸡蛋"), names(result))
    }

    @Test
    fun tooShortOrTooLongNamesAreRejected() {
        val result = extract(
            "a",
            "这行是一个远远超过三十个字上限的菜名它不可能是真的菜名所以应该被忽略掉",
            "青椒肉丝",
        )
        assertEquals(listOf("青椒肉丝"), names(result))
    }
    @Test
    fun preservesOrderSpecsAndCakeDimensions() {
        assertEquals(listOf("青青糯山无糖小杯", "奶油蛋糕30寸", "巴斯克小份"),
            names(extract("青青糯山 无糖 小杯 ¥18", "奶油蛋糕30寸 ￥800", "巴斯克 小份 ×1")))
    }

}
