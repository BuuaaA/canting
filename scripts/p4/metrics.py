from pathlib import Path
import json,hashlib,base64,unicodedata,os
r=Path(__file__).resolve().parents[2]; e=Path(os.environ.get('P4_EVIDENCE_DIR',r/'dev-docs/p4-evidence/repair-20260905')); f=r/'test/fixtures/recognition_acceptance'
def read(p): return json.loads(p.read_text(encoding='utf-8'))
def write(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
manifest=read(f/'manifest.json'); labels=read(f/'semantic-labels-v1.json')['cases']
quantity_labels=read(f/'quantity-labels-v2.json')['cases']
# No relabeling after inspecting predictions. Legacy fried-potato taxonomy has
# no explicit P2 field on old MealDish, so category is reported unavailable.
legacy={'chicken_burger':'burger','cola':'beverage'}
def metric(n,d,ids): return dict(numerator=n,denominator=d,value=n/d if d else None,status='measured' if d else 'not_measured',sample_ids=sorted(set(ids)))
def align(expected,actual):
 used=set(); pairs=[]
 for i,name in enumerate(expected):
  j=next((j for j,d in enumerate(actual) if j not in used and d['name']==name),None)
  if j is not None: used.add(j)
  pairs.append(j)
 return pairs,used
def quantity_error_indices(actual, pairs, labels):
 return {j for i,j in enumerate(pairs) if j is not None and labels[i] is not None and actual[j]['quantity'] != labels[i]}

rows=[]
for phase,filename,parserphase in [('baseline','baseline-semantic.json','baseline-parser'),('after','semantic-actual.json','parser-actual')]:
 for raw in read(e/filename):
  if raw['parser_phase']!=parserphase: continue
  cid=raw['case_id']; c=next(c for c in manifest['cases'] if c['case_id']==cid); exp=read(f/c['input_refs'][1]['path']); actual=raw['actual']; pairs,used=align(exp['names'],actual)
  stats={}; errors=[]
  def put(key,n,d): stats[key]={'numerator':n,'denominator':d}
  put('product_recall',len(used),len(exp['names'])); put('product_false_positive_rate',len(actual)-len(used),len(actual))
  for i,j in enumerate(pairs):
   if j is None: errors.append({'layer':'parser','kind':'missing','expected_index':i,'expected':exp['names'][i]})
  for j,a in enumerate(actual):
   if j not in used: errors.append({'layer':'parser','kind':'unmatched_output','actual_index':j,'actual':a['name']})
  quantity_errors=quantity_error_indices(actual,pairs,quantity_labels[cid])
  correctq=0; qden=0
  for i,j in enumerate(pairs):
   expected_quantity=quantity_labels[cid][i]
   if expected_quantity is None: continue
   qden+=1; ok=j is not None and j not in quantity_errors; correctq+=ok
   if not ok: errors.append({'layer':'parser','kind':'quantity_mismatch','expected_index':i,'expected':expected_quantity,'actual':actual[j]['quantity'] if j is not None else None})
  put('quantity_accuracy',correctq,qden)
  field_errors=set(); unavailable=[]
  for field in ['category','sugar','cup','size']:
   n=d=un=ud=na=0
   for i,label in enumerate(labels[cid]):
    wanted=label[field];j=pairs[i]
    if wanted=='not_applicable': na+=1;continue
    item=actual[j] if j is not None else {}; food=item.get('food',{});
    got=food.get('facts',{}).get('category','unknown') if field=='category' else food.get('spec',{}).get(field,'unknown')
    if field=='category' and not food and item.get('matched_dish_id'):
     got=legacy.get(item['matched_dish_id'],'unknown')
     if got=='unknown': unavailable.append({'index':i,'reason':'legacy schema has no mapped P2 category; not counted as explicit unknown assertion'})
    if wanted=='unknown':
     ud+=1; ok=j is not None and got=='unknown';un+=ok
    else:
     d+=1;ok=j is not None and got==wanted;n+=ok
    if not ok:
     field_errors.add(j); errors.append({'layer':'semantic','field':field,'expected_index':i,'expected':wanted,'actual':got,'detected':j is not None})
   put(field+'_accuracy',n,d);put(field+'_expected_unknown',un,ud)
   stats[field+'_not_applicable']={'count':na,'reason':'not a field for this product in annotation'}
  auto=[j for j,a in enumerate(actual) if a.get('matched_dish_id') or a.get('food',{}).get('decision')=='autoFill']
  wrong=sorted(set(auto) & ((set(range(len(actual)))-used) | field_errors | quantity_error_indices(actual,pairs,quantity_labels[cid])))
  put('high_confidence_wrong_auto_accept',len(wrong),len(auto));put('auto_accept_coverage',len(auto),len(exp['names']))
  put('unknown_rate',sum(not a.get('matched_dish_id') and a.get('food',{}).get('facts',{}).get('category','unknown')=='unknown' for a in actual),len(actual))
  danger=cid in ['unknown','typo','cake','quantity','meal','spec','different_specs']
  put('dangerous_auto_accept',int(bool(wrong)) if danger else 0,1 if danger else 0)
  put('ocr_text_recall',0,0);put('restart_reuse',0,0)
  rows.append({**{k:c[k] for k in ['case_id','family_id','source_kind','platform','layout','split','scenario_tags']},'run_kind':'text_replay','phase':phase,'repeat':raw['repeat'],'expected':exp,'actual':actual,'metrics':stats,'errors':errors,'category_mapping_notes':unavailable})
summary={}
for phase in ['baseline','after']:
 rr=[x for x in rows if x['phase']==phase and x['repeat']==1]; groups={'all':rr}
 for dim in ['source_kind','platform','layout','split','run_kind']:
  for v in {x[dim] for x in rr}: groups[dim+':'+v]=[x for x in rr if x[dim]==v]
 for tag in ['S%02d'%i for i in range(1,9)]:groups['scenario:'+tag]=[x for x in rr if tag in x['scenario_tags']]
 for p in ['美团','淘宝闪购/饿了么','京东外卖']:groups['real_platform:'+p]=[]
 summary[phase]={}
 keys=[k for k,v in rr[0]['metrics'].items() if 'denominator' in v]
 for key,items in groups.items():
  summary[phase][key]={'case_count':len(items),'unique_image_count':0,'product_count':sum(len(x['expected']['names']) for x in items),'metrics':{k:metric(sum(x['metrics'][k]['numerator'] for x in items),sum(x['metrics'][k]['denominator'] for x in items),[x['case_id'] for x in items if x['metrics'][k]['denominator']]) for k in keys}}
stable=all(next(x for x in rows if x['case_id']==a['case_id'] and x['phase']==a['phase'] and x['repeat']==2)['actual']==a['actual'] for a in rows if a['repeat']==1)
write(e/'case-results.json',rows);write(e/'failures.json',[{'case_id':x['case_id'],'phase':x['phase'],'repeat':x['repeat'],'errors':x['errors']} for x in rows if x['errors']]);
write(e/'metrics.json',{'schema_version':2,'run_id':e.name,'scoring_version':'v2-item-quantity-union','normalization':'exact frozen product text; only parser declared whitespace/quantity/price normalization. No fuzzy identity correction.','repeat_consistent':stable,'independent_holdout':False,'real_images':0,'groups':summary,'unmeasured':['real platform image accuracy','process kill restart','system share and camera permissions'],'restart_evidence':'Full regression local_food_flow_test opens actual SQLite again; not counted as dataset cases.','excluded_invalid_run':'invalid-semantic-no-guidelines.json: evaluator lacked guidelines, matcher was not initialized; superseded by baseline-semantic-corrected.log.'})
print(json.dumps(summary['after']['all'],ensure_ascii=False))
