import test from 'node:test';
import assert from 'node:assert/strict';
import { normalize, validIban } from './spans.mjs';
const item = (text, original, label) => ({ original, label, start: text.indexOf(original), end: text.indexOf(original)+original.length });
test('UTF16 name components become one correct UTF8 span after emoji', () => {
  const text='😀 José García';
  const result=normalize(text,[item(text,'José','GIVEN_NAME'),item(text,'García','SURNAME')]);
  assert.deepEqual(result.predictions,[{entity:'person',byte_start:5,byte_end:18}]);
  assert.equal(result.raw.length,2);
});
test('city lists stay separate while an anchored postal address joins', () => {
  const cities='Boston, Seattle';
  assert.equal(normalize(cities,[item(cities,'Boston','CITY'),item(cities,'Seattle','CITY')]).predictions.length,2);
  const address='123 Maple Street, Boston';
  assert.deepEqual(normalize(address,[item(address,'123','BUILDING_NUMBER'),item(address,'Maple Street','STREET_NAME'),item(address,'Boston','CITY')]).predictions,
    [{entity:'location',byte_start:0,byte_end:24}]);
});
test('a bank account is not automatically an IBAN', () => {
  assert(validIban('GB82 WEST 1234 5698 7654 32'));
  assert(!validIban('GB83 WEST 1234 5698 7654 32'));
  assert.equal(normalize('123456789',[item('123456789','123456789','BANK_ACCOUNT')]).predictions[0].entity,'unmapped:BANK_ACCOUNT');
});
test('malformed SDK offsets fail explicitly', () => {
  assert.throws(()=>normalize('😀',[{label:'GIVEN_NAME',original:'\ud83d',start:0,end:1}]));
});
