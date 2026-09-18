import unittest
from score import score

class ScoringTest(unittest.TestCase):
    def test_component_masking_is_not_partial_exposure_of_a_space(self):
        row={'id':'a','text':'Ada Lovelace','gold':[{'entity':'person','byte_start':0,'byte_end':12}]}
        parts=[{'entity':'person','byte_start':0,'byte_end':3},{'entity':'person','byte_start':4,'byte_end':12}]
        found={'id':'a','predictions':[row['gold'][0]],'raw_predictions':parts}
        result=score([row],[found])
        self.assertEqual(result['exact']['tp'],1)
        self.assertEqual(result['coverage']['fully_covered'],1)
    def test_wrong_type_can_cover_pii_without_an_exact_match(self):
        row={'id':'a','text':'Boston','gold':[{'entity':'location','byte_start':0,'byte_end':6}]}
        found={'id':'a','predictions':[{'entity':'person','byte_start':0,'byte_end':6}],
               'raw_predictions':[{'entity':'person','byte_start':0,'byte_end':6}]}
        result=score([row],[found])
        self.assertEqual([result['exact'][k] for k in ['tp','fp','fn']],[0,1,1])
        self.assertEqual(result['coverage']['fully_covered'],1)
    def test_unmapped_masking_on_negative_text_is_counted(self):
        result=score([{'id':'a','text':'Retry','gold':[]}],
          [{'id':'a','predictions':[],'raw_predictions':[{'entity':'unmapped:ORG','byte_start':0,'byte_end':5}]}])
        self.assertEqual(result['negative_text']['changed_rows'],1)
    def test_missing_rows_are_rejected(self):
        with self.assertRaises(ValueError): score([{'id':'a','text':'x','gold':[]}],[])

if __name__=='__main__': unittest.main()
