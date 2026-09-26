m = Map("ecm")
m.title = translate("NSS ECM Acceleration Engine")
m.description = translate("Setting NSS ECM Acceleration Engine")

s = m:section(TypedSection, "ecm", translate("Global Settings"))
s.addremove = false
s.anonymous = true

acc_nat = s:option(ListValue, "acceleration_engine", translate("Acceleration Engine"))
acc_nat.default = "auto"
acc_nat:value("auto", translate("Auto"))
acc_nat:value("nss", translate("NSS Mode"))
acc_nat:value("sfe", translate("SFE Mode"))
acc_nat:value("both", translate("NSS+SFE Hybrid Mode"))
acc_nat.description = translate("Acceleration Engine Mode")

max_con = s:option(Value, "max_con", translate("Max TCP Connection"))
max_con.datatype = "range(1,655350)"
max_con.rmempty = false
max_con.description = translate("This parameter limits the maximum number of connections that TCP can have open at the same time")
max_con.placeholder = 500000
max_con.default = 500000

bridge_acc = s:option(Flag, "bridge_acc", translate("UDP Bridge Hardware Redirect Offload"))
bridge_acc.default = "1"
bridge_acc.description = translate("Afford NATloopback/UDP Relay/Docker Network etc.")
bridge_acc.rmempty = false

return m