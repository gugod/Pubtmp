#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";


# use this block if you don't need middleware, and only have a single target Dancer app to run here
use Pubtmp;

Pubtmp->to_app;

use Plack::Builder;

builder {
    enable 'Deflater';
    Pubtmp->to_app;
}



=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use Pubtmp;
use Plack::Builder;

builder {
    enable 'Deflater';
    Pubtmp->to_app;
}

=end comment

=cut

=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use Pubtmp;
use Pubtmp_admin;

builder {
    mount '/'      => Pubtmp->to_app;
    mount '/admin'      => Pubtmp_admin->to_app;
}

=end comment

=cut

