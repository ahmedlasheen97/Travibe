import 'package:travibe/features/buddies/data/buddies_landing_data.dart';

// Test-only presentation fixtures; never displayed by the production tab.
const sampleNearbyTravelers = [
  BuddiesTraveler(
    id: 'hazem',
    name: 'Hazem Ali',
    photoAsset: 'assets/images/avatar/Ellipse 23 (1).png',
    destination: 'Bali, Indonesia',
    interests: ['Hiking', 'Road Trips'],
  ),
  BuddiesTraveler(
    id: 'khaled',
    name: 'Khaled Ali',
    photoAsset: 'assets/images/avatar/Ellipse 23 (2).png',
    destination: 'Bali, Indonesia',
    interests: ['Camping', 'Road Trips'],
  ),
  BuddiesTraveler(
    id: 'khaled-more',
    name: 'Khaled Ali',
    photoAsset: 'assets/images/avatar/Ellipse 23 (2).png',
    destination: 'Bali, Indonesia',
    interests: ['Camping', 'Road Trips'],
  ),
];
const sampleSharedInterestTravelers = [
  BuddiesTraveler(
    id: 'hazem',
    name: 'Hazem Ali',
    photoAsset: 'assets/images/avatar/Ellipse 23 (1).png',
    interests: ['Camping', 'Road Trips', 'Hiking', 'Food'],
  ),
  BuddiesTraveler(
    id: 'nora',
    name: 'Nora Ahmed',
    photoAsset: 'assets/images/avatar/Ellipse 23.png',
    interests: ['Camping', 'Road Trips', 'Hiking', 'Food'],
  ),
];
