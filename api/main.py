#!/usr/bin/env python

import asyncio
from os import environ

from aiohttp import web
import aiohttp_cors
import asyncpg

from common import *

import users

env_vars = [
    'DATABASE_HOST',
    'DATABASE_NAME',
    'DATABASE_USER',
    'DATABASE_PORT',
    'DATABASE_PASS',
]

if __name__ == '__main__':
    # Check the environment for the necessary database credentials.
    g = globals()
    for e in env_vars:
        if e in environ:
            g['db_' + e[-4:].lower()] = environ[e]
        else:
            raise KeyError('No {} environment variable found.'.format(e))

    # Are we debugging the project?
    middlewares = [manage_db]
    if 'DEBUG' in environ and to_bool(environ['DEBUG']):
        middlewares.insert(0, debug)

    loop = asyncio.get_event_loop()
    app = web.Application(middlewares=middlewares)
    app['pool'] = loop.run_until_complete(asyncpg.create_pool(
        min_size=2,
        loop=loop,
        host=db_host,
        database=db_name,
        user=db_user,
        password=db_pass,
        port=db_port,
    ))

    # Add URL endpoints here.
    app.router.add_post('/users', users.create_user)
    app.router.add_post('/users/login', users.login_user)
    app.router.add_delete('/users/logout', users.logout_user)

    # Allow unrestricted CORS in browsers.
    cors = aiohttp_cors.setup(app, defaults={
        '*': aiohttp_cors.ResourceOptions(
            allow_credentials=True,
            expose_headers='*',
            allow_headers='*',
        )
    })

    for route in list(app.router.routes()):
        cors.add(route)

    if 'PORT' in environ:
        port = int(environ['PORT'])
    else:
        port = 8001

    web.run_app(app, host='127.0.0.1', port=port)
