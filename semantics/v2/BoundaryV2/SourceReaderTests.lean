import BoundaryV2.SourceReader
import BoundaryV2.SourceEncoder

namespace BoundaryV2.Profile.SourceReaderTests

private def number (input : String) : Option Nat :=
  match SourceJson.parse (SourceJson.text input) with
  | some (.number value) => some value
  | _ => none

theorem maximum_integer_token_is_exact : number "18446744073709551615" = some 18446744073709551615 := by decide +kernel

theorem oversized_integer_token_rejects : number "18446744073709551616" = none := by decide +kernel

theorem ambiguous_integer_tokens_reject :
    ["1.0", "1e0", "01", "-0", "-1", "\"1\""].all (fun input => (number input).isNone) = true := by decide +kernel

theorem escaped_duplicate_key_rejects :
    (SourceJson.parse (SourceJson.text "{\"entry\":0,\"\\u0065ntry\":1}")).isNone = true := by decide +kernel

theorem trailing_comma_rejects :
    ["[0,]", "{\"entry\":0,}"].all (fun input => (SourceJson.parse (SourceJson.text input)).isNone) = true := by decide +kernel

def constantModule : Source.Module := {
  entry := 0, failure := 1, schemas := [.u64, .unit]
  constants := [⟨0, [5, 0, 0, 0, 0, 0, 0, 0]⟩]
  effects := [], handlers := [], regionCount := 0, resources := []
  variables := [], values := [⟨0, .literal 0⟩], terms := [.value 0]
  functions := [{ parameters := [], result := 0, body := some 0 }] }

theorem complete_module_roundtrip :
    SourceReader.decode (SourceEncoder.encode constantModule) = some constantModule := by decide +kernel

private def sparse : Bytes := SourceJson.text
  "{\"entry\":0,\"failure\":1,\"schemas\":[{\"u64\":{}},{\"unit\":{}}],\"constants\":[{\"schema\":0,\"bytes\":[5,0,0,0,0,0,0,0]}],\"effects\":[],\"handlers\":[],\"region_count\":0,\"variables\":[],\"values\":[{\"schema\":0,\"expression\":{\"literal\":0}}],\"terms\":[{\"value\":0}],\"functions\":[{\"parameters\":[],\"result\":0,\"body\":0}]}"

theorem omitted_defaults_preserve_complete_module : SourceReader.decode sparse = some constantModule := by decide +kernel

theorem unknown_module_field_rejects :
    SourceReader.decode (SourceJson.text "{\"entry\":0,\"ignored\":1}") = none := by decide +kernel

end BoundaryV2.Profile.SourceReaderTests
