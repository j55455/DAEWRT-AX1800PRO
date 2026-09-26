module("luci.controller.ecm", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/ecm") then
		return
	end

	entry({"admin", "network", "ecm"}, cbi("ecm"), _("NSS ECM"), 90).dependent = true
end