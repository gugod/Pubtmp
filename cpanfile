requires "Dancer2" => "0.205000";

requires "Imager"       => 0;
requires "Time::Moment" => 0;
requires "Digest"       => 0;
requires "Digest::SHA"  => 0;
requires "Digest::Whirlpool"  => 0;
requires "Data::UUID"  => 0;
requires "Time::Moment"  => 0;
requires "URI::Escape"  => 0;
requires "File::Next"   => 0;

recommends "YAML"             => "0";
recommends "URL::Encode::XS"  => "0";
recommends "CGI::Deurl::XS"   => "0";
recommends "HTTP::Parser::XS" => "0";

on "test" => sub {
    requires "Test::More"            => "0";
    requires "HTTP::Request::Common" => "0";
};
