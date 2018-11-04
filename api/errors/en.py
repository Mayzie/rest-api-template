en = {
    'invalid_json': {
        'code': 40000,
        'message': 'Your POST-data is not JSON-compatible.',
        'status': 400,
    },
    'missing_header': {
        'code': 40001,
        'message': "You are missing the '{}' HTTP header.",
        'status': 400,
    },
    'missing_key': {
        'code': 40002,
        'message': "You are missing the '{}' key and value in your JSON data.",
        'status': 400,
    },
    'client_error': {
        'code': 40003,
        'message': 'You did something wrong: {}.',
        'status': 400,
    },
    'server_exception': {
        'code': 50000,
        'message': 'Something went wrong on the server. Please try again shortly.',
        'status': 500,
    },
}
