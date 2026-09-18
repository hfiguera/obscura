const names = new Set(['GIVEN_NAME', 'SURNAME']);
const address = new Set(['STREET_NAME', 'BUILDING_NUMBER', 'SECONDARY_ADDRESS', 'CITY', 'STATE', 'ZIP_CODE']);
const simple = { EMAIL: 'email', PHONE: 'phone', CREDIT_CARD: 'credit_card', IP_ADDRESS: 'ip_address', URL: 'url', SSN: 'us_ssn' };
export function validIban(text) {
  const value = text.replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(value)) return false;
  let remainder = 0;
  for (const char of value.slice(4) + value.slice(0, 4)) {
    const digits = /[A-Z]/.test(char) ? String(char.charCodeAt(0) - 55) : char;
    for (const digit of digits) remainder = (remainder * 10 + Number(digit)) % 97;
  }
  return remainder === 1;
}
function byteOffset(text, offset) {
  if (!Number.isInteger(offset) || offset < 0 || offset > text.length) throw new Error('Invalid UTF16 offset');
  if (offset > 0 && offset < text.length && /[\uD800-\uDBFF]/.test(text[offset - 1]) && /[\uDC00-\uDFFF]/.test(text[offset])) throw new Error('Offset splits surrogate pair');
  return Buffer.byteLength(text.slice(0, offset));
}
export function normalize(text, items) {
  const ordered = [...items].sort((a, b) => a.start - b.start || a.end - b.end);
  const raw = ordered.map(item => {
    if (text.slice(item.start, item.end) !== item.original || item.start >= item.end) throw new Error('SDK substring mismatch');
    const entity = names.has(item.label) ? 'person' : address.has(item.label) ? 'location' :
      simple[item.label] ?? (item.label === 'BANK_ACCOUNT' && validIban(item.original) ? 'iban' : `unmapped:${item.label}`);
    return { entity, source_entity: item.label, byte_start: byteOffset(text, item.start), byte_end: byteOffset(text, item.end) };
  });
  const predictions = [];
  let group = [];
  function flush() {
    if (!group.length) return;
    const anchored = group.some(i => ['STREET_NAME', 'BUILDING_NUMBER'].includes(ordered[i].label));
    if (group.length > 1 && (names.has(ordered[group[0]].label) || anchored)) {
      predictions.push({ entity: raw[group[0]].entity, byte_start: raw[group[0]].byte_start, byte_end: raw[group.at(-1)].byte_end });
    } else for (const i of group) predictions.push({ entity: raw[i].entity, byte_start: raw[i].byte_start, byte_end: raw[i].byte_end });
    group = [];
  }
  for (let i = 0; i < ordered.length; i++) {
    if (group.length) {
      const previous = ordered[group.at(-1)], item = ordered[i];
      const gap = text.slice(previous.end, item.start);
      const adjacentNames = names.has(previous.label) && names.has(item.label) && /^\s{1,8}$/.test(gap);
      const adjacentAddress = address.has(previous.label) && address.has(item.label) && /^[\s,]{1,8}$/.test(gap);
      if (!adjacentNames && !adjacentAddress) flush();
    }
    group.push(i);
  }
  flush();
  return { raw, predictions };
}
