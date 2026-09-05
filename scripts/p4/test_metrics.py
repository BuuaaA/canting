import ast
from pathlib import Path
import unittest

class QuantityRegression(unittest.TestCase):
    def score(self, expected, actual_quantity, semantic_error=False, identified=True):
        tree=ast.parse(Path(__file__).with_name('metrics.py').read_text(encoding='utf-8'))
        expression=next(n.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='wrong' for t in n.targets))
        env={'auto':[0],'actual':[{'quantity':actual_quantity}], 'used':{0} if identified else set(), 'field_errors':{0} if semantic_error else set(), 'pairs':[0], 'cid':'quantity', 'quantity_labels':{'quantity':[expected]},'exp':{'quantity_unknown':True,'quantity':[1]}}
        functions=[n for n in tree.body if isinstance(n,ast.FunctionDef)]
        exec(compile(ast.Module(body=functions,type_ignores=[]),'metrics.py','exec'),env)
        wrong=eval(compile(ast.Expression(expression),'metrics.py','eval'),env)
        danger_expression=next(n.args[1] for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='put' and n.args and isinstance(n.args[0],ast.Constant) and n.args[0].value=='dangerous_auto_accept')
        env.update(wrong=wrong,danger=True)
        return wrong,eval(compile(ast.Expression(danger_expression),'metrics.py','eval'),env)
    def test_100_to_1(self): self.assertEqual(self.score(100,1),([0],1))
    def test_2_to_1(self): self.assertEqual(self.score(2,1),([0],1))
    def test_unlabelled_quantity(self): self.assertEqual(self.score(None,1),([],0))
    def test_multiple_errors_count_once(self): self.assertEqual(self.score(100,1,True,False),([0],1))
    def test_correct_quantity(self): self.assertEqual(self.score(2,2),([],0))
if __name__=='__main__': unittest.main()
