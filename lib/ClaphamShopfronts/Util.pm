package ClaphamShopfronts::Util;

use v5.36;
use utf8;
use Exporter 'import';
use JSON::MaybeXS qw(decode_json);
use Path::Tiny qw(path);
use Digest::SHA;
use Time::Piece;
use URI;
use HTML::Entities qw(encode_entities);
use Image::Magick;

our @EXPORT_OK = qw(read_json file_sha display_date web_url image_base html image_size unit_slug validate_slug);

sub validate_slug ($slug) {
  die "Unit slug must contain lowercase letters, digits and single hyphens\n"
    unless defined $slug && !ref $slug && $slug =~ /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/;

  return $slug;
}

sub unit_slug ($postcode, $address, $explicit = undef) {
  return validate_slug($explicit) if defined $explicit;

  my $compact = uc($postcode // '');

  $compact =~ s/\s+//g;

  die "Cannot derive a slug without a postcode; supply unit.slug\n"
    unless $compact =~ /\A([A-Z0-9]{2,4})([0-9][A-Z]{2})\z/;

  my ($outward, $inward) = ($1, $2);

  die "Cannot derive a street number from the address; supply unit.slug\n"
    unless ($address // '') =~ /^\s*(\d+[A-Za-z]?(?:\s*[-–—]\s*\d+[A-Za-z]?)?)(?=\s|,|$)/;

  my $number = $1;

  $number =~ s/\s+//g;
  $number =~ tr/–—/--/;

  return validate_slug(lc "$outward-$inward-$number");
}

sub read_json ($filename) {
  return decode_json(path($filename)->slurp_raw);
}

sub file_sha ($filename) {
  open my $fh, '<:raw', $filename or die "Cannot read $filename: $!\n";

  my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;

  close $fh or die "Cannot close $filename: $!\n";

  return $digest;
}

sub display_date ($value) {
  die "Invalid ISO date: " . ($value // '(missing)') . "\n"
    unless defined $value && $value =~ /^\d{4}-\d{2}-\d{2}$/;

  my $date = Time::Piece->strptime($value, '%Y-%m-%d');

  die "Invalid date: $value\n" unless $date->strftime('%Y-%m-%d') eq $value;

  return $date->mday . ' ' . $date->strftime('%B %Y');
}

sub web_url ($value) {
  my $url = URI->new($value);

  die "Expected an HTTP(S) URL: $value\n"
    unless ($url->scheme // '') =~ /^https?$/ && $url->can('host') && $url->host;

  return $value;
}

sub image_base ($value) {
  web_url($value) unless $value =~ m{^/(?!/)};

  die "The image base must not include a query or fragment\n" if $value =~ /[?#]/;

  $value =~ s{/+$}{};

  return "$value/";
}

sub html ($value) {
  return encode_entities($value // '', q{<>&"'});
}

sub image_size ($filename) {
  die "Published image not found: $filename\n" unless path($filename)->is_file;

  my $image = Image::Magick->new;
  my $error = $image->Read("$filename");

  die "Cannot read image $filename: $error\n" if "$error";

  return [$image->Get('width', 'height')];
}

1;
