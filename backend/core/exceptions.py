"""Exception handler DRF: приводит все ошибки API к формату {error:{code,message,details}}."""
from rest_framework.views import exception_handler


def flowers_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None:
        return None
    if "error" in response.data:
        return response

    codes = exc.get_codes() if hasattr(exc, "get_codes") else "error"
    if isinstance(codes, dict):
        code = "validation_error"
    elif isinstance(codes, (list, tuple)):
        code = codes[0] if codes else "error"
    else:
        code = codes

    response.data = {
        "error": {
            "code": code,
            "message": "Ошибка запроса",
            "details": response.data,
        }
    }
    return response
