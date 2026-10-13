package app.winters.octo.home

import app.winters.octo.lists.OctoListGroup

// The group of Octo's lists a Home shelf of mixes shows, for those shelves.
val HomeSection.mixGroup: OctoListGroup?
    get() = when (this) {
        HomeSection.YearMixes -> OctoListGroup.Years
        HomeSection.GenreMixes -> OctoListGroup.Genres
        HomeSection.ArtistMixes -> OctoListGroup.Artists
        HomeSection.CountryMixes -> OctoListGroup.Countries
        else -> null
    }

// The shelves of mixes, in Home's default order.
val MixShelves: List<HomeSection> = HomeSection.entries.filter { it.mixGroup != null }
