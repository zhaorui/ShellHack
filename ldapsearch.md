LDAP
====

    ldapsearch -L -h bill.test -b "DC=bill,DC=test" -D "CN=administrator,CN=Users,DC=bill,DC=test" -w password "objectCategory=CN=Print-Queue,CN=Schema,CN=Configuration,DC=bill,DC=test"
