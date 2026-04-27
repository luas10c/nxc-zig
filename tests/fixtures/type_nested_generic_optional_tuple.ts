type FindOperatorType = 'equal' | 'like';

type ObjectLiteral = Record<string, unknown>;

const map: Partial<Record<FindOperatorType, () => [string, ObjectLiteral?]>> = {
  equal: () => ['='],
  like: () => ['LIKE', { value: '%abc%' }],
};
