Name: 
Version:
Release:
Source:
License: GPL
Summary: Dpkg support scripts for /usr/local
Group: Utilities/System
BuildRoot: %{_tmppath}/%{name}-%{version}
BuildRequires: openssl-devel
Requires: dpkg, dpkg-dotkit, rsync, subversion, mktemp, apt, openssl-devel

%define debug_package %{nil}

%description
Dpkg support scripts for /usr/local

%prep
%setup

%build
make

%install
umask 022
mkdir -p $RPM_BUILD_ROOT%{_bindir}
for file in docreport editdeb logger mkdeb runtests getsource wrap testdeb defaults; do
    cp dpkg-${file}.sh $RPM_BUILD_ROOT%{_bindir}/dpkg-${file}
    chmod 555 $RPM_BUILD_ROOT%{_bindir}/dpkg-${file}
done
cp dpkg-verify $RPM_BUILD_ROOT%{_bindir}
cp dpkg-tmplocal $RPM_BUILD_ROOT%{_bindir}
cp dpkg-lndir $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man8
cp dpkg-tmplocal.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-lndir.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-verify.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-runtests.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-docreport.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-editdeb.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-logger.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-mkdeb.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-getsource.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-wrap.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-testdeb.8 $RPM_BUILD_ROOT%{_mandir}/man8/
cp dpkg-defaults.8 $RPM_BUILD_ROOT%{_mandir}/man8/

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-, root, root)
%doc ChangeLog NEWS
%{_bindir}/*
%{_mandir}/man8/*
%attr(04755, root, root) %{_bindir}/dpkg-tmplocal

# vi: expandtab sw=4 ts=4
