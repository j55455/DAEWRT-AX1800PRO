include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for NSS ECM Acceleration Engine
LUCI_DEPENDS:=+luci-compat +kmod-qca-nss-ecm
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-ecm
PKG_VERSION:=1
PKG_RELEASE:=6

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature