import { NavLink } from 'react-router-dom';

const LINKS = [
  { to: '/orders', label: 'Заказы' },
  { to: '/products', label: 'Товары' },
  { to: '/hours', label: 'Часы работы' },
  { to: '/finance', label: 'Финансы' },
];

/** Верхняя навигация панели: Заказы / Товары / Часы работы / Финансы. */
export default function AppNav() {
  return (
    <nav className="tabs">
      {LINKS.map((link) => (
        <NavLink
          key={link.to}
          to={link.to}
          className={({ isActive }) => `tab${isActive ? ' tab-active' : ''}`}
        >
          {link.label}
        </NavLink>
      ))}
    </nav>
  );
}
