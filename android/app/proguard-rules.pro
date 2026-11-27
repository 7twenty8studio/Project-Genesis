# kotlinx.serialization: keep the generated serializers for bibleBooks.json.
-keepclassmembers class com.genesis.core.domain.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.genesis.core.domain.**$$serializer { *; }
