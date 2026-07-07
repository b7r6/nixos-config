{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation {
  pname = "r8127";
  version = "11.015.00";

  src = fetchFromGitHub {
    owner = "minisforum-repo";
    repo = "r8127-dkms";
    rev = "7e9523a0f75ff2ee0090c4c8dc608893dea51dc9";
    hash = "sha256-VPlaLcRXrQHnJFd+hWT2q7TLnm0ogaGqAdXKukUpvN8=";
  };

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  preBuild = ''
    substituteInPlace src/Makefile --replace-fail "BASEDIR := /lib/modules/$(shell uname -r)" "BASEDIR ?= /lib/modules/$(shell uname -r)"
  '';

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "src"
    "BASEDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}"
    "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  buildFlags = [ "modules" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek
    cp src/r8127.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek/
    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/minisforum-repo/r8127-dkms";
    description = "Realtek r8127 10GbE Ethernet driver";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
