package com.ns.mefrost;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import org.json.JSONException;
import org.json.JSONObject;

public final class BrowserActivity extends Activity {
    private static final String URL = "https://www.3dhmi.com/";
    private static final String NAVIGATION_LAYOUT_SCRIPT = """
            (() => {
                if (location.protocol !== 'https:' || location.hostname !== 'www.3dhmi.com') return null;
                const nav = document.querySelector('nav.navbar');
                if (!nav) return null;
                const viewport = window.visualViewport;
                const width = viewport ? viewport.width : innerWidth;
                const height = viewport ? viewport.height : innerHeight;
                const offsetX = viewport ? viewport.offsetLeft : 0;
                const offsetY = viewport ? viewport.offsetTop : 0;
                const visible = element => {
                    const rect = element.getBoundingClientRect();
                    const style = getComputedStyle(element);
                    return rect.width > 0 && rect.height > 0 && style.visibility === 'visible'
                        && style.display !== 'none' && Number(style.opacity) > 0;
                };
                const anchor = [...nav.querySelectorAll('.navbar-toggler')].find(visible)
                    || [...nav.querySelectorAll('.nav-link')].find(visible);
                if (!anchor || !visible(nav)) return null;
                const row = anchor.getBoundingClientRect();
                const centerY = row.top + row.height / 2;
                const size = Math.max(32, Math.min(64, row.height));
                const font = Math.min(size * 0.8, parseFloat(getComputedStyle(anchor).fontSize) * 1.6);
                const rect = nav.getBoundingClientRect();
                const start = Math.max(rect.left, offsetX) + 8;
                let end = Math.min(rect.right, offsetX + width) - 8;
                const occupied = [...nav.querySelectorAll('a,button')].filter(visible)
                    .map(element => element.getBoundingClientRect())
                    .filter(r => r.bottom > centerY - size / 2 && r.top < centerY + size / 2)
                    .sort((a, b) => b.right - a.right);
                for (const item of occupied) {
                    if (item.left >= end) continue;
                    if (item.right + 8 <= end - size) break;
                    end = Math.min(end, item.left - 8);
                }
                const left = end - size - offsetX;
                const top = centerY - size / 2 - offsetY;
                if (end - size < start || top < 0 || top + size > height) return null;
                return {left, top, size, font, width, height};
            })()
            """;
    private WebView webView;
    private Button closeButton;
    private boolean trackingNavigation;
    private boolean layoutRequestPending;
    private int navigationVersion;
    private final Runnable navigationTracker = new Runnable() {
        @Override
        public void run() {
            if (!trackingNavigation || webView == null) return;
            updateCloseButtonFromNavigation();
            webView.postDelayed(this, 500);
        }
    };

    public static void open() {
        MEFrostApplication application = MEFrostApplication.getInstance();
        Intent intent = new Intent(application, BrowserActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        new Handler(Looper.getMainLooper()).post(() -> {
            Log.i("BrowserActivity", "Opening website from app main thread");
            application.startActivity(intent);
        });
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat insets = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        insets.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        insets.hide(WindowInsetsCompat.Type.systemBars());

        FrameLayout layout = new FrameLayout(this);
        layout.setBackgroundColor(Color.rgb(9, 9, 9));
        webView = new WebView(this);
        layout.addView(webView);
        TextView status = new TextView(this);
        boolean nightMode = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
            == Configuration.UI_MODE_NIGHT_YES;
        status.setTextColor(nightMode ? Color.WHITE : Color.BLACK);
        status.setBackgroundColor(Color.TRANSPARENT);
        status.setIncludeFontPadding(false);
        status.setGravity(Gravity.CENTER);
        status.setText("正在加载网页…");
        layout.addView(status);
        Button close = new Button(this);
        closeButton = close;
        close.setText("×");
        close.setContentDescription("关闭网页");
        close.setAllCaps(false);
        close.setMinWidth(0);
        close.setMinimumWidth(0);
        close.setMinHeight(0);
        close.setMinimumHeight(0);
        close.setPadding(0, 0, 0, 0);
        close.setIncludeFontPadding(false);
        close.setTextColor(Color.WHITE);
        close.setStateListAnimator(null);
        close.setElevation(0);
        close.setBackgroundTintList(null);
        close.setBackgroundColor(Color.TRANSPARENT);
        close.setOnClickListener(view -> finish());
        layout.addView(close);
        layout.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            if (right - left == oldRight - oldLeft && bottom - top == oldBottom - oldTop) return;
            float scale = Math.max(0.1f, Math.min((right - left) / 2880.0f, (bottom - top) / 1800.0f));
            webView.setLayoutParams(new FrameLayout.LayoutParams(Math.round(2880 * scale), Math.round(1800 * scale), Gravity.TOP | Gravity.CENTER_HORIZONTAL));
            FrameLayout.LayoutParams closeParams = new FrameLayout.LayoutParams(Math.round(96 * scale), Math.round(96 * scale), Gravity.TOP | Gravity.RIGHT);
            closeParams.topMargin = Math.round(16 * scale);
            int pageWidth = Math.round(2880 * scale);
            int pageLeft = ((right - left) - pageWidth) / 2;
            closeParams.rightMargin = (right - left) - pageLeft - pageWidth + Math.round(24 * scale);
            close.setLayoutParams(closeParams);
            close.setTextSize(TypedValue.COMPLEX_UNIT_PX, Math.round(64 * scale));
            close.setShadowLayer(Math.max(1, 2 * scale), 0, 0, Color.BLACK);
            FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
            statusParams.topMargin = Math.round(800 * scale);
            status.setLayoutParams(statusParams);
            status.setTextSize(TypedValue.COMPLEX_UNIT_PX, Math.round(32 * scale));
        });
        setContentView(layout);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setMediaPlaybackRequiresUserGesture(true);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !"https".equalsIgnoreCase(request.getUrl().getScheme());
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                navigationVersion++;
                resetCloseButtonLayout();
                status.setText("正在加载网页…");
                status.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                updateCloseButtonFromNavigation();
                if ("正在加载网页…".contentEquals(status.getText())) {
                    status.setVisibility(View.GONE);
                }
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    status.setText("网页加载失败，请检查网络后关闭重试。");
                    status.setVisibility(View.VISIBLE);
                }
            }
        });
        webView.loadUrl(URL);
    }

    private void resetCloseButtonLayout() {
        if (webView == null || webView.getWidth() == 0) return;
        float scale = webView.getWidth() / 2880.0f;
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(Math.round(96 * scale), Math.round(96 * scale), Gravity.TOP | Gravity.LEFT);
        params.leftMargin = webView.getLeft() + webView.getWidth() - Math.round(120 * scale);
        params.topMargin = webView.getTop() + Math.round(16 * scale);
        closeButton.setLayoutParams(params);
        closeButton.setTextSize(TypedValue.COMPLEX_UNIT_PX, Math.round(64 * scale));
    }

    private void updateCloseButtonFromNavigation() {
        if (webView == null || !trackingNavigation || layoutRequestPending || webView.getWidth() == 0) return;
        WebView current = webView;
        int version = navigationVersion;
        layoutRequestPending = true;
        current.evaluateJavascript(NAVIGATION_LAYOUT_SCRIPT, result -> {
            layoutRequestPending = false;
            if (webView != current || !trackingNavigation || version != navigationVersion) return;
            try {
                JSONObject rect = new JSONObject(result);
                double width = rect.getDouble("width");
                double height = rect.getDouble("height");
                double left = rect.getDouble("left");
                double top = rect.getDouble("top");
                double size = rect.getDouble("size");
                double font = rect.getDouble("font");
                if (!Double.isFinite(width + height + left + top + size + font)
                        || width <= 0 || height <= 0 || left < 0 || top < 0 || size < 32 || size > 64
                        || font <= 0 || font > size || left + size > width || top + size > height) {
                    resetCloseButtonLayout();
                    return;
                }
                double scaleX = current.getWidth() / width;
                double scaleY = current.getHeight() / height;
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                        (int) Math.round(size * scaleX), (int) Math.round(size * scaleY), Gravity.TOP | Gravity.LEFT);
                params.leftMargin = current.getLeft() + (int) Math.round(left * scaleX);
                params.topMargin = current.getTop() + (int) Math.round(top * scaleY);
                closeButton.setLayoutParams(params);
                closeButton.setTextSize(TypedValue.COMPLEX_UNIT_PX, (float) (font * Math.min(scaleX, scaleY)));
            } catch (JSONException exception) {
                resetCloseButtonLayout();
            }
        });
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onPause() {
        trackingNavigation = false;
        if (webView != null) webView.removeCallbacks(navigationTracker);
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
        trackingNavigation = true;
        if (webView != null) webView.post(navigationTracker);
    }

    @Override
    protected void onDestroy() {
        trackingNavigation = false;
        if (webView != null) {
            webView.removeCallbacks(navigationTracker);
            ((FrameLayout) webView.getParent()).removeView(webView);
            webView.stopLoading();
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
