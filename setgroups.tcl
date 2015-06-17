package require ade_lib

bind [adinfo domain] administrator ldap4$

set group "btgroup"

set btg_dn "CN=$group,OU=Temp,DC=new,DC=test" 
catch {create_adgroup $btg_dn $group "global"}

for {set i 1 } {$i <= 1000} {incr i 1} {
    set dn "CN=$group$i,OU=Temp,DC=new,DC=test"
    create_adgroup $dn $group$i "global"
    add_user_to_group $group$i@new.test $group@new.test
}
