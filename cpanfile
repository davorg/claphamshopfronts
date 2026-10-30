requires 'perl', '5.036';
requires 'DBIx::Class';
requires 'Moose';
requires 'MooseX::NonMoose';
requires 'MooseX::MarkAsMethods';
requires 'MooX::Role::SEOTags', '1.2.1';
requires 'MooX::Role::JSON_LD', '2.1.0';
requires 'DBD::SQLite';
requires 'Template';
requires 'JSON::MaybeXS';
requires 'Path::Tiny';
requires 'Image::Magick';
requires 'Image::ExifTool';
requires 'URI';
requires 'HTML::Entities';

on 'test' => sub {
  requires 'Test::More';
  requires 'HTML::Parser';
};

on 'develop' => sub {
  requires 'DBIx::Class::Schema::Loader';
  requires 'App::HTTPThis';
};
