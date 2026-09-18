import unittest
from adapter import combine

def span(entity,a,b,**kw):return dict(entity=entity,byte_start=a,byte_end=b,**kw)
class MergeTests(unittest.TestCase):
 def test_full_address_replaces_only_contained_location(self):
  base={'id':'a','predictions':[span('person',0,4),span('location',10,14)],'raw_predictions':[span('person',0,4),span('location',10,14)]}
  redact={'predictions':[span('location',8,25)],'raw_predictions':[span('location',8,14,source_entity='STREET_NAME'),span('location',20,25,source_entity='CITY')]}
  result=combine(base,redact)
  self.assertEqual(result['predictions'],[span('person',0,4),span('location',8,25)])
  self.assertFalse(any(p['byte_start']<=15<p['byte_end'] for p in result['raw_predictions']))
 def test_city_alone_is_not_enrichment(self):
  base={'id':'a','predictions':[],'raw_predictions':[]}
  redact={'predictions':[span('location',0,5)],'raw_predictions':[span('location',0,5,source_entity='CITY')]}
  self.assertEqual(combine(base,redact)['predictions'],[])
 def test_child_error_is_visible(self):
  self.assertIn('error',combine({'id':'a','error':'failed'},{}))
if __name__=='__main__':unittest.main()
