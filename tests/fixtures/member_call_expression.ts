const ALLOWED_TYPES = [String, Boolean, Number, Array, Object];

function validate(metatype: unknown, type: Function) {
    if (!metatype || !ALLOWED_TYPES.includes(type)) {
        return false;
    }

    return true;
}

const result = validate(String, String);

console.log(result);
