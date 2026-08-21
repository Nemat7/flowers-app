from rest_framework import generics

from .models import Banner
from .serializers import BannerSerializer


class BannerListView(generics.ListAPIView):
    """GET /banners/ — активные баннеры главного экрана (api.md §2)."""

    serializer_class = BannerSerializer
    pagination_class = None  # карусель забирает все баннеры разом
    queryset = Banner.objects.filter(is_active=True)
