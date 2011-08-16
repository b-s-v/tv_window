#!/usr/bin/perl -w

use strict;
use CGI qw(:cgi);
use FindBin qw($Bin);
use lib "$Bin/lib";
#use CGI::Carp 'fatalsToBrowser';
use Getopt::Std;

# Cleaning
our %opts = ();
getopts('c',\%opts);

if ( $opts{ c } ) {
   Cleaning->new->run();

   exit;
}




our $_store = undef;

my $q = CGI->new()->Vars();
my $lmod     = $q->{'lmod'};
my $referrer = $q->{'r'}    || 0;
my $ajax     = $q->{'ajax'} || 0;
my $request  = '';
$lmod = int $lmod if $lmod;

# OUTSIDE
if ( $referrer ) {
   my $outside = Outside->new( $referrer );
   $request = $outside->{ request };
   my $r = 0;
   $r = $outside->save()
      if $outside->{ request } && $outside->{ searcher }
   ;
   print "Content-type: text/plain; charset=utf-8\n\n";
   print "result = [$r]";


}

# INSIDE
elsif ( defined $lmod ) {
   my $inside = Inside->new( {ajax => $ajax, lmod => $lmod} );
   $inside->send();
}
else {
   print "Content-type: text/plain; charset=utf-8\n\n";
   print 'empty';
}





################# CONFIG #######################
sub CONFIG_PATH {"$Bin/etc/tv_window.conf"}

##########################
sub _read_config {
   my $fname = shift;
   open my $fh, "<", $fname or die "failed to read config $fname: $!";
   while ( <$fh> ) {
      chomp;
      s/(?<!\\)#.*//g;
      next if /^\s*$/;
      next unless /\=/;
      my ($k, $v) = split '=', $_, 2;
      next unless $k =~ /./ && $v =~ /./;
      $_ =~ s/^\s*|\s*$//g for ($k, $v);
      $_store->{$k} = $v;
   } # while
   close $fh or die $!;
}

##########################
sub config {
   my $opt_name = shift;

   unless ( defined $_store ) {
      # Читаем конфиг
      $_store = {};
      _read_config( CONFIG_PATH() );
   } # if
   return $opt_name ? $_store->{$opt_name} : $_store;
}





################### AObject #####################
# Родительский класс с общими методами
package AObject;

use strict;
use DBI;
use Convert::Cyrillic;
#use CGI::Carp 'fatalsToBrowser';

##########################
sub new {
   my $class = shift;
   my $self = bless {
      input => $_[0],
      searcher_dict => {
         rambler => {id => 0, short => 'r', get_name => 'query'},
         yandex  => {id => 1, short => 'y', get_name => 'text'},
         google  => {id => 3, short => 'g', get_name => 'q'},
         mail    => {id => 5, short => 'm', get_name => 'q'},
      },
      searcher_short => {
         0 => 'r',
         1 => 'y',
         3 => 'g',
         5 => 'm',
      },
   }, $class;
   #yahoo   => {id => 4, short => 'y', get_name => 'p'},
   #aport   => {id => 2, short => 'a', get_name => 'r'},
   #2 => 'a',
   $self->_init;

   return $self;
}

##########################
sub _init {
   my $self = shift;

   my $data_source = 'dbi:'.
                     main::config('db_type').':'.
                     main::config('db_name').':'.
                     main::config('db_host').':'.
                     main::config('db_port');
                     #warn "mysql $data_source";
   $self->{ _dbh } = DBI->connect(# сделать чтение параметров db из конфигурационного файла!!!!!!!!!!
                                  $data_source,
                                  main::config('db_login'),
                                  main::config('db_password')
                                 ) or die "Соединение с базой невозможно. Reason: ", $DBI::errstr;
   my $sth = $self->{ _dbh }->prepare(qq!set names !.lc( main::config('page_charset') ))# кодировку читать из конфигурационного файла!!!!!!!!!!!
      or die $self->{ _dbh }->errstr;
   $sth->execute()
      or die $sth->errstr;
}

##########################
sub change_encoding {
   my $self = shift;
   my $c    = shift;
   #warn "change_encoding: content [$c]";

   my $destiny_charset = $_[0] || 'UTF8';

   #перенаправляем STDERR из-за большого колва сообщений при определении кодировки UTF строки
   open( OLDSTDERR,  ">&STDERR" ) or die "Can't open OLDSTDERR: $!";
   open( STDERR,     "+>/dev/null" ) or die "Can't open STDERR: $!";
   my $charset         = Lingua::DetectCharset::Detect( $c );
   #восстанавливаем STDERR
   close STDERR;
   open( STDERR,     ">&OLDSTDERR" ) or die "Can't open STDERR: $!";
   close OLDSTDERR;
   #warn "destiny_charset [$destiny_charset], charset [$charset]";

   if ($charset ne 'ENG' && uc($charset) ne uc($destiny_charset)) {
      $c = Convert::Cyrillic::cstocs( $charset, $destiny_charset, $c );
   }
   return $c;
}

##########################
sub dbh {
   my $self = shift;
   return $self->{_dbh};
}

##########################
sub DESTROY {
   my $self = shift;
   $self->dbh->disconnect if ref $self->dbh;
}

1;



################### Inside #####################
# отдаёт на страницу в ajax последние запросы из базы раз в минуту
package Inside;
use base qw(AObject);

use strict;
use Data::Dumper qw(Dumper);

##########################
sub _init {
   my $self = shift;

   $self->SUPER::_init;

   $self->{ num_request } = 14;
   $self->{ num_request } = 3 if $self->{input}{lmod};
}

##########################
sub send {
   my $self = shift;

   my $data = $self->_get_data();
   my $xml  = $self->_create_xml( $data );

   print "Content-type: text/xml; charset=utf-8\n\n";
   print $xml;

}

##########################
sub _get_data {
   my $self = shift;
   my $data = {};
   $data->{ request }       = $self->_get_request();
   $data->{ searcher_stat } = $self->_get_searcher_stat();
   return $data;
}

##########################
sub _get_searcher_stat {
   my $self = shift;
   my %searcher_stat = ();
   my $query = qq!
SELECT searcher, stat
FROM tv_window_searcher_stat
   !;
   my $sth = $self->dbh->prepare($query) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   $sth->execute || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;

   my $summ = 0;
   while ( my ($searcher, $stat) = $sth->fetchrow_array ) {
      $searcher_stat{ $searcher } = $stat;
      $summ                      += $stat
   }
   $searcher_stat{ summ } = $summ;
   $sth->finish;

   return \%searcher_stat;
}

##########################
sub _get_request {
   my $self = shift;
   my @request = ();
   my $query = qq!
SELECT id, searcher, request, date
FROM tv_window
   !;
   my $sth;
   if ($self->{ num_request } == 3) {
      $query .= qq! WHERE id > ? ORDER BY id DESC LIMIT $self->{ num_request }!;
      #warn "[$query] [$self->{input}{lmod}]";
      $sth = $self->dbh->prepare($query) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
      $sth->execute($self->{input}{lmod}) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   }
   else {
      $query .= qq!              ORDER BY id DESC LIMIT $self->{ num_request }!;
      #warn "[$query]";
      $sth = $self->dbh->prepare($query) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
      $sth->execute() || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   }

   while ( my ($id, $searcher, $request, $date) = $sth->fetchrow_array ) {
      push @request, {
                     id       => $id,
                     searcher => $searcher,
                     request  => $request,
                     date     => $date,
                  };
   }
   $sth->finish;
   @request = reverse @request;
   return \@request;
}

##########################
sub _create_xml {
   my $self = shift;
   my $data = shift;

   my $xml = '<nochanges>empty</nochanges>';
   return $xml
      unless    ref $data
          &&       %$data
          && exists $data->{ request }
          &&    ref $data->{ request }
          &&     @{ $data->{ request } }
   ;

   my $xml_request = '';
   foreach (@{ $data->{ request } }) {
      #warn Dumper($_);
      $xml_request   .= qq!<t s="!.
         $self->{ searcher_short }->{ $_->{ searcher } }
      .qq!">!.
         ($self->change_encoding($_->{ request }, main::config('page_charset')) || ' ')
      .qq!</t>!;
   }
   $xml_request = qq!<terms>$xml_request</terms>!;

   my $xml_searcher_stat = '<se><y>0</y><g>0</g><r>0</r><m>0</m></se>';
   if (exists $data->{ searcher_stat } && %{ $data->{ searcher_stat } }) {
      $xml_searcher_stat = qq!<se><y>!.
         ($data->{ searcher_stat }{$self->{ searcher_dict }->{ yandex  }{ id }} || 0) .qq!</y><g>!.
         ($data->{ searcher_stat }{$self->{ searcher_dict }->{ google  }{ id }} || 0) .qq!</g><r>!.
         ($data->{ searcher_stat }{$self->{ searcher_dict }->{ rambler }{ id }} || 0) .qq!</r><m>!.
         ($data->{ searcher_stat }{$self->{ searcher_dict }->{ mail    }{ id }} || 0) .qq!</m></se>!;
   }

   $xml = qq!<traff total="!.
      $data->{ searcher_stat }{ summ  } .qq!" term="!.
      $data->{ request }[-1]{ request } .qq!" lmod="!.
      $data->{ request }[-1]{ id      } .qq!">!.
      $xml_searcher_stat . $xml_request
   .qq!</traff>!;

   return $xml;
}


1;

################### Outside #####################
# реагирует на запросы, записывает в базу запросы и поисковики, ведёт статистику (тоже в базе)
package Outside;                                         # DONE
use base qw(AObject);

use strict;
use URI::Escape qw(uri_unescape);
use Lingua::DetectCharset;
use Convert::Cyrillic;
use Encode;
use utf8;
use Data::Dumper qw(Dumper);

=pod
CREATE TABLE tv_window (
   id       int(15) unsigned NOT NULL auto_increment,
   searcher int(2) NOT NULL,
   request  text NOT NULL,
   date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8


CREATE TABLE tv_window_searcher_stat (
   searcher int(2) NOT NULL,
   stat     int(10),
   UNIQUE  (searcher)
) ENGINE=InnoDB DEFAULT CHARSET=utf8


# not need
CREATE TABLE tv_window_mark_cleaning (
   tbl_name   text NOT NULL,
   clean_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   UNIQUE    (tbl_name(10))
) ENGINE=InnoDB DEFAULT CHARSET=utf8

=cut


##########################
sub save {
   my $self = shift;

   $self->_save_request;
   $self->_save_searcher_stat;


   print "Content-type: text/plain; charset=utf-8\n\n";
   print 'save';
}

##########################
sub _save_request {
   my $self = shift;
   my $query = qq!INSERT tv_window (searcher, request) VALUES(?,?)!;
   my $sth = $self->dbh->prepare( $query )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;

   #warn "_save_request: request [$self->{ request  }]";

   $sth->execute(
      $self->{ searcher_dict }->{ $self->{ searcher } }{ id },
      $self->{ request  },
   ) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
}


##########################
sub _save_searcher_stat {
   my $self = shift;
   my ($searcher_id, $count) = @_;
   return 0
      if !$searcher_id &&
         !(
            grep {
               $_ eq $self->{ searcher }
            } keys %{ $self->{ searcher_dict } }
         );

   # get exists searcher stat
   unless ( $searcher_id && $count ) {
      $searcher_id = $self->{ searcher_dict }->{ $self->{ searcher } }{ id };
      $count       = 1;

      my $searcher_stat = $self->_get_exists_searcher_stat();
      $count           += $searcher_stat->{ $searcher_id };
   }

   # save searcher stat
   my $query = qq!
INSERT tv_window_searcher_stat (searcher, stat)
VALUES(?,?)
ON DUPLICATE KEY UPDATE stat = ?
   !;
   my $sth = $self->dbh->prepare( $query )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;

   $sth->execute(
      $searcher_id,
      $count,
      $count,
   ) || die 'Dont connect to mysql: '. $sth->errstr .'. '. $query;

}

##########################
sub _get_exists_searcher_stat {
   my $self = shift;
   my $searcher_stat = {};

   my $query = qq!SELECT searcher, stat FROM tv_window_searcher_stat!;
   my $sth = $self->dbh->prepare($query) || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   $sth->execute || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;

   while ( my ($searcher, $stat) = $sth->fetchrow_array ) {
      $searcher_stat->{ $searcher } = $stat;
   }
   $sth->finish;

   return $searcher_stat;
}

##########################
sub _init {
   my $self = shift;

   $self->SUPER::_init;

   my ( $searcher, $request ) = $self->_parse_referrer();
   #warn "[$searcher], [$request]\n";
   $self->{ searcher } = $searcher;
   $self->{ request  } = $request;
}

##########################
sub _parse_referrer {
   my $self = shift;
   my ($s, $r) = ('','');

   my $referrer = $self->{ input };
   #warn "referrer [$referrer]\n";

   $referrer = uri_unescape( $referrer ) if $referrer;
   #warn "referrer #[$referrer]#\n";

   # search SEARCHER
   ( $s ) = grep {
      $referrer =~ /$_/
   } keys %{ $self->{ searcher_dict } };
   #warn "searcher [$s]\n";
   return $s, $r unless $s;


   # search REQUEST
   my $rq = $self->{ searcher_dict }->{ $s }{ get_name };
   my $qr = qr#$rq=([^&]+)&?#;
   #warn "rq [$rq] qr [$qr]\n";

   $r = $1 if $referrer =~ /$qr/;
   #$r = Encode::decode('utf8', $r);# Encode::_utf8_off($r);# Encode::decode('cp1251', $r);
   #utf8::decode( $r );
   $r = $self->change_encoding( $r, 'utf8' );
   $r =~ s/\+/ /g;
   #warn "r [$r] s [$s]\n";

   return $s, $r;
}


1;




################### Cleaning #####################
# Запускается по крону в 01-00, удаляет из базы устаревшие на 24 часа и с id меньше последнего на 20 рефереры и чистит таблицу статистики, если есть флаг в файле конфигурации
package Cleaning;                                         # DONE
use base qw(AObject);

use strict;
use Data::Dumper qw(Dumper);



##########################
sub run {
   my $self = shift;

   $self->_clean_request;
   $self->_clean_stat if main::config( 'auto_clean' );
}

##########################
sub _clean_request {
   my $self = shift;
   #warn "_clean_request";

   my $query_max = qq!SELECT max(id) FROM tv_window!;
   my $sth_max = $self->dbh->prepare($query_max)
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_max;
   $sth_max->execute()
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_max;
   my $max_id = $sth_max->fetchrow_array;
   $sth_max->finish;
   return unless $max_id;

   my $query = qq!
DELETE FROM tv_window
WHERE date < DATE_SUB(NOW(), INTERVAL 24 HOUR)
AND id < (? - ?)
   !;
   my $sth = $self->dbh->prepare($query)
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   $sth->execute( $max_id, main::config( 'offset' ) )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;
   $sth->finish;
}

##########################
sub _clean_stat {
   my $self = shift;

   # check time
   #my $hour = (localtime)[2];
   #return if $hour != 18;# for test? after test - 
   warn "_clean_stat";

   # check date of clean
   #my $day = sprintf '%02d', (localtime)[3];
   #my $date_clean = $self->__check_date_of_clean();
   #return if $date_clean && $date_clean =~ /^\d\d\d\d-\d\d\-$day/;
   warn "Start\n";

   # clean stat
   $self->__clean_stat();

   # count for today
   my $date_count = $self->__count_for_today();

   # save stat by today
   $self->__save_searcher_stat( $_, $date_count->{ $_ } )
      foreach keys %$date_count;

   # mark clean
   #$self->__mark_clean_stat();# clean by cron, not need save date of cleaning
}

##########################
sub __save_searcher_stat {
   my $self = shift;
   my ($searcher_id, $count) = @_;
   return 0 if $searcher_id && $count;


   # save searcher stat
   my $query = qq!
INSERT tv_window_searcher_stat (searcher, stat)
VALUES(?,?)
ON DUPLICATE KEY UPDATE stat = ?
   !;
   my $sth = $self->dbh->prepare( $query )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query;

   $sth->execute(
      $searcher_id,
      $count,
      $count,
   ) || die 'Dont connect to mysql: '. $sth->errstr .'. '. $query;

}

##################
sub __check_date_of_clean {# not need
   my $self = shift;
   my $query_check = qq!SELECT clean_date FROM tv_window_mark_cleaning WHERE tbl_name = 'stat'!;
   my $sth = $self->dbh->prepare( $query_check )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_check;
   $sth->execute()
      || die 'Dont connect to mysql: '. $sth->errstr       .'. '. $query_check;
   my $date_clean = $sth->fetchrow_array;
   $sth->finish();
   return $date_clean;
}

##################
sub __clean_stat {
   my $self = shift;
   my $query_clean = qq!DELETE FROM tv_window_searcher_stat!;
   my $sth = $self->dbh->prepare( $query_clean )
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_clean;
   $sth->execute()
      || die 'Dont connect to mysql: '. $sth->errstr       .'. '. $query_clean;
   $sth->finish();
}

##################
sub __count_for_today {
   my $self = shift;
   my $query_count = qq!SELECT count(*), searcher FROM tv_window t GROUP BY searcher!;
   my $sth = $self->dbh->prepare($query_count)
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_count;
   $sth->execute()
      || die 'Dont connect to mysql: '. $sth->errstr       .'. '. $query_count;
   my $date_count = {};
   while (my ($seacher_count, $searcher_id) = $sth->fetchrow_array) {
      $date_count->{ $searcher_id } = $seacher_count;
   }
   $sth->finish();
   return $date_count;
}

##################
sub __mark_clean_stat {# not need
   my $self = shift;
   my $tbl_name = shift;
   return unless $tbl_name;

   my $query_mark  = qq!
INSERT INTO tv_window_mark_cleaning (tbl_name, clean_date)
VALUES(?, NOW())
ON DUPLICATE KEY UPDATE clean_date = NOW()
   !;
   my $sth = $self->dbh->prepare($query_mark)
      || die 'Dont connect to mysql: '. $self->dbh->errstr .'. '. $query_mark;
   $sth->execute( $tbl_name )
      || die 'Dont connect to mysql: '. $sth->errstr       .'. '. $query_mark;
}

1;
