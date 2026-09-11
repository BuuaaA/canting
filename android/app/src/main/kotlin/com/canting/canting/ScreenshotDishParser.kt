package com.canting.canting

data class OcrLine(val text: String, val left: Int?, val top: Int?, val right: Int?, val bottom: Int?)

/** Pure OCR layout stage: distinct from recognition and food classification. */
object ScreenshotDishParser {
    private val fee = Regex("""^(?:打包费|包装费|餐盒费|配送费|合计|总计|实付|应付)""")
    private val quantity = Regex("""^[×xX]\s*(\d+)$""")
    private val spec = Regex("""^(?:[（(]\d|(?:大杯|中杯|小杯|超大杯|无糖|少糖|半糖|三分糖|正常糖|冰|热|大份|小份|正常份)(?:[（(/、，,\s]|$))""")

    fun extract(lines: List<OcrLine>): DishExtractionResult {
        if (lines.isEmpty()) return DishExtractionResult("", emptyList())
        if (lines.any { it.left == null || it.top == null || it.right == null || it.bottom == null }) {
            val result = DishNameExtractor.extract(lines.map { it.text })
            return result.copy(dishes = result.dishes.map { it.copy(requiresConfirmation = true) },
                warnings = result.warnings + "缺少版面位置，请核对商品与页面说明是否混入")
        }
        val sorted = lines.sortedWith(compareBy<OcrLine> { it.top }.thenBy { it.left })
        val cart = sorted.firstOrNull { it.text.trim().startsWith("加入购物车") || it.text.trim().startsWith("加入购物袋") }
        val description = sorted.firstOrNull { it.text.trim().startsWith("商品描述") || it.text.trim().startsWith("商品详情") }
        if (cart != null && description != null && description.top!! > cart.bottom!!) {
            // A detail page's title sits beside its cart button. Spatial selection also
            // excludes food names in recommendations below the product description.
            val height = cart.bottom!! - cart.top!!
            val title = sorted.filter {
                it.left!! < cart.left!! && it.top!! >= cart.top!! - height * 2 &&
                    it.bottom!! <= minOf(description.top!!, cart.bottom!! + height * 2) &&
                    !DishNameExtractor.shouldExclude(it.text) &&
                    DishNameExtractor.extract(listOf(it.text)).dishes.isNotEmpty()
            }
            val result = DishNameExtractor.extract(listOf(title.joinToString("") { it.text }))
            return result.copy(dishes = result.dishes.map { it.copy(requiresConfirmation = true) },
                warnings = result.warnings + "商品详情页不代表已下单，请核对商品、组合内容与份量")
        }

        val merchant = sorted.firstOrNull { DishNameExtractor.isMerchantLine(it.text) && !DishNameExtractor.shouldExclude(it.text) }
        val end = merchant?.let { m -> sorted.firstOrNull { it.top!! > m.bottom!! && fee.containsMatchIn(it.text.trim()) } }
        if (merchant != null && end != null) {
            return order(sorted.filter { it.top!! >= merchant.bottom!! && it.bottom!! <= end.top!! }, merchant.text)
        }
        // Unknown layouts stay editable; they are not silently treated as confirmed food.
        val result = DishNameExtractor.extract(sorted.map { it.text })
        return result.copy(dishes = result.dishes.map { it.copy(requiresConfirmation = true) },
            warnings = result.warnings + "版面暂未确认，请核对并删除非商品内容")
    }

    private fun order(lines: List<OcrLine>, merchant: String): DishExtractionResult {
        val products = mutableListOf<ExtractedDish>()
        val warnings = linkedSetOf<String>()
        var title: OcrLine? = null
        val specs = mutableListOf<String>()
        val quantities = mutableListOf<String>()
        fun flush() {
            val product = title ?: return
            val parsed = DishNameExtractor.extract(listOf(product.text))
            warnings.addAll(parsed.warnings)
            parsed.dishes.firstOrNull()?.let { base ->
                val detailedSpecs = specs.any { it.contains('/') }
                // A trailing x2 may be an ingredient count. Only the final quantity
                // after earlier ingredient counts is used; unresolved single counts
                // in a detailed recipe remain in the raw spec for review.
                val ambiguousCount = detailedSpecs && quantities.size == 1
                val countText = if (ambiguousCount) null else quantities.lastOrNull()
                val count = countText?.let { quantity.matchEntire(it)?.groupValues?.get(1)?.toIntOrNull() }
                val invalid = countText != null && (count == null || count !in 1..99)
                val extra = if (countText == null) quantities else quantities.dropLast(1)
                val name = base.name + specs.joinToString("") { it.replace(" ", "") } + extra.joinToString("/")
                if (invalid || ambiguousCount) warnings.add("商品数量与规格数量可能混淆，请核对原图")
                products.add(base.copy(name = name + if (invalid) countText else "",
                    quantity = if (invalid || count == null) base.quantity else count,
                    requiresConfirmation = base.requiresConfirmation || specs.isNotEmpty() || invalid || ambiguousCount))
            }
            title = null; specs.clear(); quantities.clear()
        }
        for (line in lines) {
            val text = line.text.trim()
            if (DishNameExtractor.shouldExclude(text)) continue
            val parent = title
            val sameColumn = parent != null && kotlin.math.abs(line.left!! - parent.left!!) <= (parent.bottom!! - parent.top!!) * 2
            if (sameColumn && quantity.matches(text)) {
                quantities.add(text)
            } else if (sameColumn && (spec.containsMatchIn(text) || text.contains('/'))) {
                specs.add(text)
            } else if (DishNameExtractor.extract(listOf(text)).dishes.isNotEmpty()) {
                flush(); title = line
            }
        }
        flush()
        if (products.size > 20) warnings.add("仅处理前20项，请手动补充其余商品")
        val hasCombo = products.any { it.name.contains("套餐") || it.name.contains('+') || it.name.contains('＋') }
        return DishExtractionResult(merchant.trim().removePrefix("闪购"), products.take(20).map {
            if (hasCombo) it.copy(requiresConfirmation = true) else it
        }, warnings.toList())
    }
}
