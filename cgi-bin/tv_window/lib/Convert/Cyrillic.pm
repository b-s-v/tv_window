# Package Convert::Cyrillic
# Version 1.02
# Part of "Cyrillic Software Suite"
# Get docs and newest version from
#	http://www.neystadt.org/cyrillic/
#
# Copyright (c) 1997-98, John Neystadt <http://www.neystadt.org/john/>
# You may install this script on your web site for free
# To obtain permision for redistribution or any other usage
#	contact john@neystadt.org.
#
# Drop me a line if you deploy this script on tyour site.

package Convert::Cyrillic;

$VERSION = "1.02";

=head1 NAME

Convert::Cyrillic v1.02 - Routines for converting from one cyrillic charset to another.

=cut

use Unicode::Map8;
use Unicode::String;

$UCase {'KOI'} = "��������������������������\377�����";
$LCase {'KOI'} = "�����ţ��������������������������";
$UCase {'WIN'} = "�����Ũ��������������������������";
$LCase {'WIN'} = "�������������������������������\377";
$UCase {'DOS'} = "���������������������������������";
$LCase {'DOS'} = "������񦧨�����������������������";

$tab{"KOI8"}="��������������������������\377����������ţ��������������������������";
$tab{"DOS"}="���������������������������������������񦧨�����������������������";
$tab{"ISO"}="������������������������������������������������������������������";
$tab{"WIN"}="�����Ũ���������������������������������������������������������\377";
$tab{"VOL"}="ABVGDE��ZIJKLMNOPRSTUFXC��W~Y'���abvgde��zijklmnoprstufxc��w~y'��\377";
$tab{"MAC"}="������݆����������������������������������������������������������";
#	     1234567890123456789012345678901234567890123456789012345678901234567890

sub cstocs {
	my ($Src, $Dst, $Buf) = @_;
	$Src = uc ($Src); $Src .= '8' if $Src eq 'KOI';
	$Dst = uc ($Dst); $Dst .= '8' if $Dst eq 'KOI';

	if ($Src eq 'UTF8') {
		my $map = Unicode::Map8->new("cp1251");
		
		$Buf = $map->to8 (Unicode::String::utf8 ($Buf)->ucs2);
		$Src = 'WIN';
	}

	if ($Dst eq 'UTF8') {
		eval "\$Buf =~ tr/$tab{$Src}/$tab{'WIN'}/";
		my $map = Unicode::Map8->new("cp1251");
		$Buf = $map->tou ($Buf)->utf8;
	} else {
		eval "\$Buf =~ tr/$tab{$Src}/$tab{$Dst}/";
	}

	if ($Dst eq 'VOL') {
		$Buf =~s/�/YO/go; $Buf =~s/�/ZH/go; $Buf =~s/�/CH/go;
		$Buf =~s/�/SH/go; $Buf =~s/�/E\'/go; $Buf =~s/�/YU/go; 
		$Buf =~s/�/YA/go; $Buf =~s/�/yo/go; $Buf =~s/�/zh/go;  
		$Buf =~s/�/ch/go; $Buf =~s/�/sh/go; $Buf =~s/�/e\'/go; 
		$Buf =~s/�/yu/go; $Buf =~s/\377/ya/go;
	}
	$Buf;
}

sub toLower {
	my ($s, $Code) = @_;
	$Code = uc ($Code);
	if (exists $UCase {$Code} and exists $LCase {$Code}) {
		eval ("\$s =~ tr/$UCase{$Code}/$LCase{$Code}/");
	}

	$s;
}

sub toUpper {
	my ($s, $Code) = @_;
	$Code = uc ($Code);
	if (exists $UCase {$Code} and exists $LCase {$Code}) {
		eval ("\$s =~ tr/$LCase{$Code}/$UCase{$Code}/");
	}

	$s;
}

__END__

=head1 SYNOPSIS

	use Convert::Cyrillic;

	$src = 'koi8';
	$dst = 'win';
	$SrcBuf = 'text in koi8 here';
	$DstBuf = Convert::Cyrillic::cstocs ($Src, $Dst, $SrcBuf); 

=head1 DESCRIPTION

This package implements routine for converting from one cyrillic charset to 
another. It is intended to be used from cgi's which need built-in support for
translations. For example, you may wish to use it in form processor to translate 
from user encoding to one used by your site.

Where B<$Src> and B<$Dst> are one of: 

	KOI8 - for KOI8-R 
	WIN - for WIN-1251 
	DOS - for DOS, alternative, CP-866 
	MAC - for Macintosh 
	ISO - for ISO-8859-5 
	UTF-8 - for UTF-8 (Unicode)
	VOL - for Volapuk (transliteration) 

Buffer may contain line breaks, which are preserved.

=head1 NOTES

Part of "WWW Cyrillic Encoding Suite"
Get docs and newest version from
	http://www.neystadt.org/cyrillic/

Copyright (c) 1997-98, John Neystadt <http://www.neystadt.org/john/>
You may install this script on your web site for free.
To obtain permision for redistribution or any other usage
contact john@neystadt.org.

Drop me a line if you deploy this script on your site.

=head1 AUTHOR

John Neystadt <john@neystadt.org>

=head1 SEE ALSO

perl(1), Lingua::DetectCharset(3).

=cut
