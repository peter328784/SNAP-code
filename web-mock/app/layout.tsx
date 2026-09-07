import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'S.N.A.P Smart Valet Demo',
  applicationName: 'S.N.A.P Smart Valet',
  description:
    'Raspberry Pi 연동을 준비한 S.N.A.P 체류 시간 기반 원터치 무인 발렛 Web Mock',
  openGraph: {
    title: 'S.N.A.P Smart Valet Demo',
    description: '설치 없이 주차·출차 흐름과 Raspberry Pi 연결을 보여주는 반응형 Web Mock',
    type: 'website',
    locale: 'ko_KR',
    images: [
      {
        url: '/snap-social-preview.png',
        width: 1200,
        height: 630,
        alt: 'S.N.A.P Smart Valet 차량별 원터치 입차·출차',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'S.N.A.P Smart Valet Demo',
    description: '차량별 예상 주차시간을 반영하는 고객용 원터치 입차·출차 데모',
    images: ['/snap-social-preview.png'],
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: '#0d1f22',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
