use Test::More tests => 1;

use lib "lib";
use lib "../lib";

BEGIN {
use_ok( 'Apache::Logmonster' );
}

diag( "Testing Apache::Logmonster $Apache::Logmonster::VERSION" );

Apache::Logmonster::new( conf=>{foo=>"bar"} );
