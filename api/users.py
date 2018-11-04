from aiohttp import web

from common import *

from uuid import UUID

import bcrypt

from validation import *

async def login_user(request):
    db = request['db']
    if not request.body_exists:
        return Error('no_body')
    data = await request.json()

    (identifier,
    input_password) = parse_body(
        data,
        ('identifier', str.lower, True),
        ('password', str, True),
    )

    (user_id,
    password,
    login_type,
    created,
    updated,
    name,
    data) = await db.get_user_details(identifier)

    if not bcrypt.checkpw(bytes(input_password, encoding='utf-8'), bytes(password, encoding='ascii')):
        raise Error('user_not_found')

    token, expires = await db.user_login(user_id)

    return {
        'user_id': from_uuid(user_id),
        'login_method': login_type,
        'created': created.isoformat(),
        'last_updated': updated.isoformat(),
        'name': name,
        'data': data if data else {},
        'token': token,
        'expires': expires.isoformat(), 
    }, 200

@validate_user
async def logout_user(request, user_id, token):
    db = request['db']

    await db.user_logout(user_id, token)

    return {}, 200

async def create_user(request):
    db = request['db']

    if not request.body_exists:
        raise Error('no_body')
    data = await request.json()

    (identifier,
    password,
    login_method,
    name,
    data) = parse_body(
        data,
        ('identifier', validate_identifier, True),
        ('password', str, True),
        ('login_method', validate_login_method, True),
        ('full_name', str, True),
        ('data', dict, False),
    )

    try:
        if login_method == 'email':
            identifier = validate_email(identifier)
        elif login_method == 'phone':
            identifier = validate_phone_number(identifier)
    except:
        raise Error('invalid_type', 'identifier', login_method)

    async with db.conn.transaction() as t:
        values = [
            'name', name,
        ]

        user_id = await db.create_object(
            'users',
            values,
        )

        password = bcrypt.hashpw(bytes(password, encoding='utf-8'), bcrypt.gensalt(10))

        success = await db.add_user_identity(user_id, login_method, identifier, str(password, 'ascii'))

        # ToDo: Consolidate into one function.
        success = await db.add_user_permission(user_id, user_id, 'update')
        success = await db.add_user_permission(user_id, user_id, 'update')
        success = await db.add_user_permission(user_id, user_id, 'delete')

    return {
        'user_id': from_uuid(user_id),
    }, 200
