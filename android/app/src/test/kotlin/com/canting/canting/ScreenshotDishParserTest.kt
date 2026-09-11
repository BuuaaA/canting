package com.canting.canting

import java.util.Base64
import org.junit.Assert.*
import org.junit.Test

class ScreenshotDishParserTest {
    private fun fixture(name: String): List<OcrLine> = javaClass.classLoader!!
        .getResourceAsStream("ocr-layout/$name.tsv")!!.bufferedReader().useLines { rows ->
            rows.map { row ->
                val p = row.split('\t')
                OcrLine(String(Base64.getDecoder().decode(p[4]), Charsets.UTF_8),
                    p[0].toInt(), p[1].toInt(), p[2].toInt(), p[3].toInt())
            }.toList()
        }

    @Test fun realDetailScreenshotContainsOneComboNotSixteenUiLabels() {
        val result = ScreenshotDishParser.extract(fixture("case2"))
        assertEquals(listOf("香干肉丝盖浇饭+饮料"), result.dishes.map { it.name })
        assertEquals(1, result.dishes.single().quantity)
        assertTrue(result.dishes.single().requiresConfirmation)
    }

    @Test fun realCheckoutRetainsOnlyPurchasedCoffeeAndItsSpecs() {
        val result = ScreenshotDishParser.extract(fixture("case1"))
        assertEquals(1, result.dishes.size)
        val coffee = result.dishes.single()
        assertTrue(coffee.name.contains("熔岩维也纳咖啡"))
        assertTrue(coffee.name.contains("473"))
        assertTrue(coffee.name.contains("全脂牛奶"))
        assertEquals(1, coffee.quantity)
        assertFalse(coffee.name.contains("提拉米苏"))
        assertTrue(result.merchant.contains("星巴克"))
    }

    @Test fun geometryWorksWhenOcrBlockOrderChangesAndImageIsRescaled() {
        for (name in listOf("case1", "case2")) {
            val lines = fixture(name)
            val expected = ScreenshotDishParser.extract(lines)
            assertEquals(expected, ScreenshotDishParser.extract(lines.reversed()))
            val scaled = lines.map { it.copy(left=it.left!!*2, top=it.top!!*2,
                right=it.right!!*2, bottom=it.bottom!!*2) }
            assertEquals(expected, ScreenshotDishParser.extract(scaled))
        }
    }

    @Test fun unknownProductTitleSurvivesWithoutFoodKeywordWhitelist() {
        val lines = fixture("case2").map {
            if (it.text.contains("香干肉丝")) it.copy(text="【超值】青青糯山") else it
        }
        assertEquals(listOf("青青糯山"), ScreenshotDishParser.extract(lines).dishes.map { it.name })
    }

    @Test fun detailMetadataWithoutAProductTitleDoesNotInventFood() {
        val lines = fixture("case2").filterNot { it.text.contains("香干肉丝") }
        assertTrue(ScreenshotDishParser.extract(lines).dishes.isEmpty())
    }

    @Test fun missingBoundsFallbackStillFiltersRecognizedUiLabels() {
        val lines = fixture("case2").map { it.copy(left=null, top=null, right=null, bottom=null) }
        assertEquals(listOf("香干肉丝盖浇饭+饮料"), ScreenshotDishParser.extract(lines).dishes.map { it.name })
    }

    private fun row(text: String, top: Int, left: Int = 100) = OcrLine(text,left,top,left+200,top+30)

    @Test fun ordinaryMultiItemOrderKeepsDistinctProductsAndCounts() {
        val result = ScreenshotDishParser.extract(listOf(row("邻里小馆",100),
            row("青椒肉丝×2",200), row("米饭",300), row("×3",340), row("合计¥39",420)))
        assertEquals(listOf(ExtractedDish("青椒肉丝",2),ExtractedDish("米饭",3)), result.dishes)
    }

    @Test fun ingredientCountCannotSilentlyBecomeNumberOfCoffees() {
        val result = ScreenshotDishParser.extract(listOf(row("星巴克(测试店)",100),
            row("拿铁咖啡",200), row("大杯/全脂牛奶/浓缩份数",240), row("x2",280),row("合计¥39",360)))
        assertEquals(1, result.dishes.single().quantity)
        assertTrue(result.dishes.single().requiresConfirmation)
        assertTrue(result.dishes.single().name.contains("x2"))
        assertTrue(result.warnings.isNotEmpty())
    }

    @Test fun foodNamedRecommendationBelowDescriptionIsNotAnOrderedItem() {
        val result = ScreenshotDishParser.extract(fixture("case2") + row("招牌红烧肉",2340))
        assertEquals(listOf("香干肉丝盖浇饭+饮料"), result.dishes.map { it.name })
    }

    @Test fun comboHeaderAndChildrenInAnOrderAllRemainUnresolved() {
        val result = ScreenshotDishParser.extract(listOf(row("邻里小馆",100),
            row("汉堡套餐",200),row("香辣鸡腿堡",260),row("可乐",320),row("合计¥39",400)))
        assertEquals(3, result.dishes.size)
        assertTrue(result.dishes.all { it.requiresConfirmation })
        assertTrue(result.warnings.isNotEmpty())
    }
}
