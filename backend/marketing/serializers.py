from rest_framework import serializers

from .models import Banner


class BannerSerializer(serializers.ModelSerializer):
    """Баннер главного экрана (api.md §2, макет v5 01-home)."""

    class Meta:
        model = Banner
        fields = ("id", "title", "tag", "image", "link_type", "link_value")
