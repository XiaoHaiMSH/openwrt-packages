include $(TOPDIR)/rules.mk

PKG_NAME          := luci-app-podman
PKG_VERSION:=20261106
PKG_RELEASE:=1
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_URL           := https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman
PKG_MAINTAINER    := Christopher Söllinger <christopher.soellinger@gmail.com>
PKG_LICENSE       := Apache-2.0
PKG_LICENSE_FILES := LICENSE


LUCI_TITLE         := LuCI Podman Application
LUCI_DESCRIPTION   := LuCI Support for podman
LUCI_DEPENDS       := +luci-base +rpcd +rpcd-mod-ucode +ucode-mod-socket +ucode-mod-struct +ucode-mod-uloop +ucode-mod-fs +ucode-mod-html +ucode-mod-uci +liblucihttp-ucode +coreutils-timeout
LUCI_PKGARCH       := all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
