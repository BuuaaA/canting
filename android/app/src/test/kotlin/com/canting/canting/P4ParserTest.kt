package com.canting.canting
import org.junit.Test
import org.junit.Assert.*
class P4ParserTest {
 @Test fun threeDigitQuantityNeverBecomesTen() {
  val r=DishNameExtractor.extract(listOf("米饭×100"))
  assertFalse(r.dishes.any { it.quantity == 10 || it.name == "米饭0" })
 }
 @Test fun separateSpecsBelongToProduct() {
  val r=DishNameExtractor.extract(listOf("青青糯山", "三分糖 大杯", "×2", "配送费 ¥3"))
  assertEquals(listOf(ExtractedDish("青青糯山三分糖大杯",2)),r.dishes)
 }
 @Test fun invalidAndOverflowQuantitiesRequireReview() {
  for (q in listOf("0","100","999999999999999999999")) {
   val r=DishNameExtractor.extract(listOf("米饭×$q"))
   assertTrue(r.warnings.isNotEmpty())
   assertTrue(r.dishes.single().requiresConfirmation)
   assertTrue(r.dishes.single().name.contains(q))
  }
 }
 @Test fun truncationAndComboAreVisible() {
  val r=DishNameExtractor.extract((1..22).map { "未知商品${it}号" })
  assertEquals(20,r.dishes.size); assertTrue(r.warnings.any { it.contains("20") })
  val combo=DishNameExtractor.extract(listOf("汉堡套餐","香辣鸡腿堡","可乐"))
  assertTrue(combo.dishes.all { it.requiresConfirmation })
 }
 @Test fun differentSpecsNeverMergeAndSameSpecsSum() {
  val r=DishNameExtractor.extract(listOf("奶茶无糖小杯×1","奶茶正常糖大杯×2","奶茶无糖小杯×2"))
  assertEquals(listOf(3,2),r.dishes.map { it.quantity })
 }
}
