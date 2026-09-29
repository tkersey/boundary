"""Parser/model guards only; these tests do not provide SMT equivalence proof."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("search", Path(__file__).parents[1] / "tools/bitvector_search.py")
search = importlib.util.module_from_spec(spec)
spec.loader.exec_module(search)

def source():
    return {"format": "boundary-bitvectors/v1", "image_identity": "0"*64, "encoding_complete": True, "evaluation": "total-straight-line-eager", "input_domain": "all-bit-patterns", "nodes": [
        {"opcode": "input", "bits": 8, "schema": 0, "input": 0, "operands": []},
        {"opcode": "input", "bits": 8, "schema": 0, "input": 1, "operands": []},
        {"opcode": "integer_bit_xor", "bits": 8, "schema": 0, "operands": [0,1]},
        {"opcode": "integer_bit_xor", "bits": 8, "schema": 0, "operands": [2,0]},
    ], "result": 3}

class Guards(unittest.TestCase):
    def test_unknown_timeout_error_and_contradiction_are_not_proof(self):
        for stdout, code, timeout in [("unknown",0,False),("unsat",0,True),("unsat",1,False),("unsat\n(error bad)",0,False),("unsat\nsat",0,False),("",0,False)]:
            self.assertEqual(search.classify(stdout,code,timeout)["status"],"not-proved")

    def test_exhaustive_diagnostic_does_not_claim_width_parametric_proof(self):
        result=search.finite_counterexample(source(),("arg",1))
        self.assertEqual(result["status"],"no-small-counterexample")
        self.assertEqual(result["cases"],256)
        self.assertFalse(result["proof"])

    def test_false_rule_has_actual_width_minimal_small_counterexample(self):
        result=search.finite_counterexample(source(),("arg",0))
        self.assertEqual(result["status"],"refuted")
        self.assertEqual(result["inputs"],(0,1))
        self.assertNotEqual(result["source"],result["target"])

    def test_incomplete_encoding_and_wrong_operand_width_reject(self):
        for kind in ("incomplete","width","version","opcode"):
            value=copy.deepcopy(source())
            if kind=="incomplete": value["encoding_complete"]=False
            elif kind=="width": value["nodes"][1]["bits"]=16
            elif kind=="version": value["nodes"][2]["operands"]=[3,0]
            else: value["nodes"][2]["opcode"]="integer_add"
            with self.assertRaises(ValueError): search.validate(value)

    def test_model_replay_and_minimization_are_independent(self):
        values=search.model_values("sat\n((x0 #xff) (x1 (_ bv0 8)))",2)
        self.assertEqual(values,[255,0])
        result=search.minimize(source(),("arg",0),values)
        self.assertTrue(result["minimization_complete"])
        self.assertNotEqual(result["source"],result["target"])
        self.assertIsNone(search.model_values("sat\n((x0 #x01))",2))

    def test_query_is_exact_width_and_deterministic(self):
        first=search.query(source(),("arg",1),1000)
        self.assertEqual(first,search.query(source(),("arg",1),1000))
        self.assertIn("(_ BitVec 8)",first)
        self.assertIn("(assert (not (= s3 x1)))",first)

if __name__ == "__main__": unittest.main()
