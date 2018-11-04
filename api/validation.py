# Common validation methods to be used when parsing user input.
#
# Any exceptions raised will be caught and discarded, only resulting in
# an "invalid_value" error response (if used within the parse_body() 
# method -- see common.py).

import phonenumbers
import email_validator

from dateutil.parser import parse as parse_ts

def validate_login_method(method):
    if method.lower() in ['email', 'phone']:
        return method.lower()

    raise Exception

def validate_user_type(user_type):
    if user_type.lower() in ['patient', 'carer', 'users']:
        return user_type.lower()

    raise Exception

def validate_date(date):
    p_date = parse_ts(date, dayfirst=True, yearfirst=True)

    return p_date.date()

def validate_timestamp(timestamp):
    return parse_ts(timestamp, dayfirst=True, yearfirst=True)

def validate_phone_number(phone_number, default_country='AU'):
    pn = phonenumbers.parse(phone_number, default_country)
    if not phonenumbers.is_possible_number(pn):
        raise Exception
    if not phonenumbers.is_valid_number(pn):
        raise Exception

    return phonenumbers.format_number(pn, phonenumbers.PhoneNumberFormat.E164)

def validate_email(email):
    p_email = email_validator.validate_email(email)

    return p_email['email']

def validate_between(min, max):
    def func(value):
        return min <= value <= max

    return func

validate_identifier = lambda x: str(x).lower()
