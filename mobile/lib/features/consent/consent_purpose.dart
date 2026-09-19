enum ConsentPurpose {
  age18Plus('age_18_plus', required: true),
  terms('terms', required: true),
  history('history'),
  media('media'),
  voice('voice'),
  location('location');

  const ConsentPurpose(this.wire, {this.required = false});

  final String wire;
  final bool required;
}
