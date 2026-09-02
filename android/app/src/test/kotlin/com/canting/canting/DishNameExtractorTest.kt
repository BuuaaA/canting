package com.canting.canting

import org.junit.Assert.assertEquals
import org.junit.Test

class DishNameExtractorTest {
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
                ExtractedDish(name = "黄焖鸡米饭", quantity = 2),
                ExtractedDish(name = "清炒时蔬", quantity = 1),
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
}
