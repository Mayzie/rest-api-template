
from aiohttp import web

# Necessary for exception handling.
from aiohttp.web_exceptions import HTTPClientError
from json.decoder import JSONDecodeError
from asyncpg.exceptions import RaiseError

import uuid
import base64
import traceback
import functools

import sys
import datetime

from json import dumps, loads

from errors import errors


default_lang = 'en'
accepted_langs = ['en']

# Empty database class, attributes to be assigned later.
class Database:
    pass


# Error class that is used to provide application error messages to the end user.
class Error(Exception):
    def __init__(self, key, *args):
        self.key = key
        self.args = args


# Converts a long-winded UUID to a nice short string.
def from_uuid(id: uuid) -> str:
    return str(base64.urlsafe_b64encode(id.bytes), 'utf-8').rstrip('=')

# Converts a nice short string to a long-winded UUID.
def to_uuid(id: str) -> uuid:
    id = base64.urlsafe_b64decode(bytes(id + ('=' * (len(id) % 4)), 'utf-8'))

    return uuid.UUID(bytes=id)

# Convert a value to a boolean data type (because Python's bool() type-cast isn't as nice).
to_bool = lambda b: (
    # Check if boolean equals to an acceptable True value
    True if str(b).lower() in ['true', 'yes', 'y', 't'] else
    (
        # Check if boolean equals to an acceptable False value
        False if str(b).lower() in ['false', 'no', 'f', 'n'] else
        # else raise this fantastic exception.
        (_ for _ in ()).throw(Exception("'{}' is not a valid boolean value.".format(str(b))))
    )
)

# Read a (JSON) dictionary for listed keys, and convert them if necessary.
# Raise an exception if a key does not exist, should the third parameter of
# the tuple(s) be True.
#
# e.g:
# parse_body({'hello': '123'},
#      ('hello', int, True)  # Look for key 'hello', typecast value to int. Raise
# )                          # exception if it doesn't exist.
def parse_body(body, *args):
    if not isinstance(body, dict):
        raise TypeError('Dictionary-like object expected as first argument. Got {}.'.format(type(body).__name__))

    result = []
    for t in args:
        if not isinstance(t, tuple) or not len(t) == 3:
            raise ValueError('Arguments need to be a tuple with three elements.')

        if t[0] not in body:
            if t[2]:
                raise Error('missing_key', t[0])

            result.append(None)
            continue

        if t[0] in body:
            try:
                result.append(t[1](body[t[0]]))
            except:
                raise Error('invalid_value', body[t[0]], t[0])

    if len(result) > 1:
        return tuple(result)
    else:
        return result[0]

# Necessary because Postgres requires cursor objects to be wrapped in a transaction.
async def call_db_proc(connection, statement, *args):
    result = None
    async with connection.transaction():
        result = await statement(*args)

    return result

# Establish a connection to the database pool and setup any stored procedures / prepared
# statements to be called by the application.
async def setup_pg(connection):
    await connection.set_builtin_type_codec('hstore', codec_name='pg_contrib.hstore')

    statements = {
        # Table name, key-value list
        'create_object': (connection.prepare('SELECT TMP.CreateObject($1::TEXT, VARIADIC $2::TEXT[])'), 'fetchval'),
        # User identifier
        'get_user_details': (connection.prepare('SELECT TMP.GetUserDetails($1::TEXT)'), 'fetchval'),
        # User ID
        'user_login': (connection.prepare('SELECT TMP.UserLogin($1::UUID)'), 'fetchval'),
        # User ID
        'user_logout': (connection.prepare('SELECT TMP.UserLogout($1::UUID, $2::TEXT)'), 'fetchval'),
        # User ID, Session Token
        'validate_user': (connection.prepare('SELECT TMP.ValidateUser($1::UUID, $2::TEXT)'), 'fetchval'),
        # User ID, Login Type, Identifier, Password
        'add_user_identity': (connection.prepare('SELECT TMP.AddUserIdentity($1::UUID, $2::TMP.LOGINTYPE, $3::TEXT, $4::TEXT)'), 'fetchval'),
    }

    db = Database()
    db.conn = connection

    for key, value in statements.items():
        statement = await value[0]
        setattr(db, key, getattr(statement, value[1]))

    return db

# Returns a friendly error dictionary (for the end-user / client application)
# given an error key and arguments.
def get_error(error_id=None, *args):
    if error_id in errors[default_lang]:
        e = errors[default_lang][error_id]
        return {
            'error': {
                'name': error_id,
                'code': e['code'],
                'desc': e['message'].format(*args),
            },
        }, e['status']
    else:
        return get_error('server_exception')

# Convert the response returned by a method (e.g. `create_user`) into
# an acceptable response that can be read by the end user / client.
#
# This method should _never_ fail, otherwise all hell will break loose (just kidding,
# the end user / client won't get a nicely formatted error message =( ).
def convert_json_response(resp):
    if len(resp) > 1 and isinstance(resp[1], int):
        status = resp[1]
    else:
        status = 200

    if len(resp) > 2 and isinstance(resp[2], dict):
        resp_headers = resp[2]
    else:
        resp_headers = None

    try:
        if isinstance(resp, tuple):
            resp = dumps(resp[0])
        else:
            resp = dumps(resp)
    except Exception as e:
        print(str(e))
        return convert_json_response(get_error())

    return web.Response(status=status, headers=resp_headers, text=resp, content_type='application/json')

# Handle an incoming request by a client.
@web.middleware
async def manage_db(request, handler):
    pool = request.app['pool']

    async with pool.acquire() as connection:
        request['db'] = await setup_pg(connection)

        try:
            resp = await handler(request)
            if isinstance(resp, web.Response):
                return resp
            else:
                return convert_json_response(resp)
        except RaiseError as err:  # An error in a Postgres stored procedure.
            error = str(err).split(' ')
            error_id = error[0]
            if len(error) > 1:
                args = error[1:]
            else:
                args = []

            return convert_json_response(get_error(error_id, *args))
        except Error as err:  # HTTP error raised by us, the devs! (e.g. user_not_found)
            return convert_json_response(get_error(err.key, *err.args))
        except HTTPClientError as err:  # Client error (e.g. requested resource not found).
            return convert_json_response(get_error('client_error', str(err)))
        except JSONDecodeError:
            return convert_json_response(get_error('invalid_json'))
        except Exception as err:  # Server error. Log the error to stderr to be looked at a later date in
            traceback.print_exc() # the system logs.

            return convert_json_response(get_error('server_exception'))

@web.middleware
async def debug(request, handler):
    result = await handler(request)
    print('{} -- Hit from {}: {} - {} {}'.format(datetime.datetime.now().strftime('%I:%M:%S %p'),
        request.remote, result.status, request.method, request.rel_url), flush=True)

    if result.status != 200:
        print('Headers: ', flush=True, file=sys.stderr)
        print(dumps(dict(request.headers.items()), indent=4, sort_keys=True), flush=True, file=sys.stderr)

        if request.body_exists and request.can_read_body:
            data = await request.text()

            print('', file=sys.stderr, flush=True)
            print('Body:', flush=True, file=sys.stderr)
            print(data, flush=True, file=sys.stderr)

        print('', file=sys.stderr, flush=True)
        print('Result:', file=sys.stderr, flush=True)
        print(dumps(loads(result.text), indent=4, sort_keys=True), file=sys.stderr, flush=True)

    print('', file=sys.stderr, flush=True)

    return result

def validate_user(func):
    async def wrapper(request):
        db = request['db']

        if not request.headers.get('user-id'):
            raise Error('missing_header', 'User-ID')
        if not request.headers.get('authorization'):
            raise Error('missing_header', 'Authorization')

        try:
            user_id = to_uuid(request.headers.get('user-id'))
        except:
            raise Error('invalid_user_id', request.headers.get('user-id'))

        token = request.headers.get('authorization')

        token_valid = await db.validate_user(user_id, token)
        if not token_valid:
            raise Error('invalid_token', token)

        return await func(request, user_id=user_id, token=token)

    return wrapper
